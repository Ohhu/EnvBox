//go:build windows

// Package appenv exposes the active profile as an executable environment.
//
// On macOS the equivalent service reads ~/.envbox/active.zsh produced by the app.
// Windows has no login shell: the applied environment is the registry, and the
// vault is the source of truth for what should be there. This package answers
// "what does the active profile look like right now" for both the CLI and MCP.
package appenv

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"os"
	"os/exec"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/Ohhu/EnvBox/internal/model"
	"github.com/Ohhu/EnvBox/internal/vault"
)

// DefaultMaxOutputBytes caps captured stdout/stderr per stream.
const DefaultMaxOutputBytes = 256 * 1024

// DefaultTimeout bounds a single exec call.
const DefaultTimeout = 60 * time.Second

// VarDescription is the secret-free view of one variable.
type VarDescription struct {
	Name        string `json:"name"`
	Length      int    `json:"length"`
	Fingerprint string `json:"fingerprint"`
}

// Description is what env_describe returns.
type Description struct {
	Available  bool             `json:"available"`
	Generation string           `json:"generation"`
	Profile    string           `json:"profile,omitempty"`
	Count      int              `json:"count"`
	Vars       []VarDescription `json:"vars"`
	Missing    []string         `json:"missing,omitempty"`
}

// Result is the outcome of one command.
type Result struct {
	ExitCode  int
	Stdout    []byte
	Stderr    []byte
	Truncated bool
	TimedOut  bool
}

// Provider reads the vault and runs commands inside the active profile.
type Provider struct {
	Store          *vault.Store
	MaxOutputBytes int
}

// NewProvider wires the default vault store.
func NewProvider() (*Provider, error) {
	store, err := vault.NewStore()
	if err != nil {
		return nil, err
	}
	return &Provider{Store: store, MaxOutputBytes: DefaultMaxOutputBytes}, nil
}

// Payload loads the vault payload.
func (p *Provider) Payload() (*model.VaultPayload, error) {
	if p.Store == nil {
		return nil, errors.New("appenv: 未配置配置库")
	}
	return p.Store.Load()
}

// Active returns the active profile together with a generation marker.
// The generation is derived from the applied fingerprint so callers can tell
// whether the environment changed between two calls.
func (p *Provider) Active() (*model.EnvProfile, string, error) {
	payload, err := p.Payload()
	if err != nil {
		return nil, "", err
	}
	profile := payload.ActiveProfile()
	generation := ""
	if payload.AppliedFingerprint != nil && len(*payload.AppliedFingerprint) >= 12 {
		generation = (*payload.AppliedFingerprint)[:12]
	} else if profile != nil {
		generation = profile.Fingerprint()[:12]
	}
	return profile, generation, nil
}

// Describe reports names, lengths and fingerprints. Values never leave this package.
func (p *Provider) Describe(keys []string) (*Description, error) {
	profile, generation, err := p.Active()
	if err != nil {
		return nil, err
	}
	if profile == nil {
		return &Description{Available: false, Generation: generation}, nil
	}

	vars := profile.EnabledVariables()
	byName := make(map[string]model.EnvVariable, len(vars))
	for _, v := range vars {
		byName[strings.ToUpper(v.TrimmedKey())] = v
	}

	description := &Description{Available: true, Generation: generation, Profile: profile.Name, Count: len(vars)}
	if len(keys) == 0 {
		for _, name := range sortedNames(vars) {
			v := byName[strings.ToUpper(name)]
			description.Vars = append(description.Vars, VarDescription{
				Name: name, Length: len(v.Value), Fingerprint: Fingerprint(v.Value),
			})
		}
		return description, nil
	}

	for _, key := range keys {
		key = strings.TrimSpace(key)
		if key == "" {
			continue
		}
		v, ok := byName[strings.ToUpper(key)]
		if !ok {
			description.Missing = append(description.Missing, key)
			continue
		}
		description.Vars = append(description.Vars, VarDescription{
			Name: v.TrimmedKey(), Length: len(v.Value), Fingerprint: Fingerprint(v.Value),
		})
	}
	return description, nil
}

// Value returns the plaintext value; only env_reveal calls this, after a policy check.
func (p *Provider) Value(key string) (string, bool, error) {
	profile, _, err := p.Active()
	if err != nil {
		return "", false, err
	}
	if profile == nil {
		return "", false, nil
	}
	want := strings.ToUpper(strings.TrimSpace(key))
	for _, v := range profile.EnabledVariables() {
		if strings.ToUpper(v.TrimmedKey()) == want {
			return v.Value, true, nil
		}
	}
	return "", false, nil
}

// MergedEnvironment layers the active profile over the current process environment.
// Windows compares variable names case-insensitively, so the key is upper case.
func (p *Provider) MergedEnvironment() ([]string, error) {
	profile, _, err := p.Active()
	if err != nil {
		return nil, err
	}
	return MergeEnvironment(os.Environ(), profile), nil
}

// MergeEnvironment is exported so tests and the CLI share one implementation.
func MergeEnvironment(base []string, profile *model.EnvProfile) []string {
	merged := make(map[string]string, len(base)+16)
	order := make([]string, 0, len(base)+16)
	for _, kv := range base {
		idx := strings.Index(kv, "=")
		if idx <= 0 {
			continue
		}
		name := strings.ToUpper(kv[:idx])
		if _, seen := merged[name]; !seen {
			order = append(order, name)
		}
		merged[name] = kv[idx+1:]
	}
	if profile != nil {
		for _, v := range profile.EnabledVariables() {
			name := strings.ToUpper(v.TrimmedKey())
			if _, seen := merged[name]; !seen {
				order = append(order, name)
			}
			merged[name] = v.Value
		}
	}
	out := make([]string, 0, len(order))
	for _, name := range order {
		out = append(out, name+"="+merged[name])
	}
	return out
}

// Execute runs command through cmd.exe with the merged environment.
//
// The command string is passed to `cmd /d /s /c`, which is the same shell an
// MCP client would get from a terminal, so pipelines and redirection behave as
// the user expects. Output is captured with a hard cap.
func (p *Provider) Execute(ctx context.Context, command string, timeout time.Duration) (*Result, error) {
	if strings.TrimSpace(command) == "" {
		return nil, errors.New("appenv: 缺少 command")
	}
	if timeout <= 0 {
		timeout = DefaultTimeout
	}
	env, err := p.MergedEnvironment()
	if err != nil {
		return nil, err
	}

	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	cmd := exec.CommandContext(ctx, "cmd.exe", "/d", "/s", "/c", command)
	cmd.Env = env
	limit := p.MaxOutputBytes
	if limit <= 0 {
		limit = DefaultMaxOutputBytes
	}
	stdout := &cappedBuffer{limit: limit}
	stderr := &cappedBuffer{limit: limit}
	cmd.Stdout = stdout
	cmd.Stderr = stderr
	cmd.Stdin = nil

	runErr := cmd.Run()
	result := &Result{
		Stdout:    stdout.Bytes(),
		Stderr:    stderr.Bytes(),
		Truncated: stdout.truncated || stderr.truncated,
	}
	if ctx.Err() == context.DeadlineExceeded {
		result.TimedOut = true
		result.ExitCode = -1
		return result, nil
	}
	if runErr != nil {
		var exitErr *exec.ExitError
		if errors.As(runErr, &exitErr) {
			result.ExitCode = exitErr.ExitCode()
			return result, nil
		}
		return nil, runErr
	}
	return result, nil
}

// Fingerprint is a stable, non-reversible digest used instead of a value.
func Fingerprint(value string) string {
	if value == "" {
		return "sha256:"
	}
	sum := sha256.Sum256([]byte(value))
	return "sha256:" + hex.EncodeToString(sum[:])[:16]
}

func sortedNames(vars []model.EnvVariable) []string {
	names := make([]string, 0, len(vars))
	for _, v := range vars {
		names = append(names, v.TrimmedKey())
	}
	sort.Slice(names, func(i, j int) bool { return strings.ToUpper(names[i]) < strings.ToUpper(names[j]) })
	return names
}

// cappedBuffer keeps at most limit bytes and remembers that it dropped data.
type cappedBuffer struct {
	mu        sync.Mutex
	buf       bytes.Buffer
	limit     int
	truncated bool
}

func (b *cappedBuffer) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	remaining := b.limit - b.buf.Len()
	if remaining <= 0 {
		b.truncated = true
		return len(p), nil
	}
	if len(p) > remaining {
		b.buf.Write(p[:remaining])
		b.truncated = true
		return len(p), nil
	}
	b.buf.Write(p)
	return len(p), nil
}

func (b *cappedBuffer) Bytes() []byte {
	b.mu.Lock()
	defer b.mu.Unlock()
	return append([]byte(nil), b.buf.Bytes()...)
}

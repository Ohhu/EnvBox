//go:build windows

// Package shell owns the opt-in PowerShell integration, the Windows equivalent of
// the macOS ~/.zshrc hook.
//
// Why it exists at all: a new terminal started from Explorer inherits the updated
// registry environment, but a terminal started from an already-running shell
// inherits the parent process environment and would keep stale values. Dot-sourcing
// %LOCALAPPDATA%\EnvBox\active.ps1 from $PROFILE fixes that case.
//
// The activation file is plaintext by necessity (PowerShell has to read it),
// exactly like active.zsh on macOS. That boundary is documented, not hidden.
package shell

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/Ohhu/EnvBox/internal/fsx"
	"github.com/Ohhu/EnvBox/internal/model"
	"github.com/Ohhu/EnvBox/internal/winsys"
)

// Managed markers must stay stable: older files are matched by them.
const (
	MarkerStart = "# >>> EnvBox shell integration >>>"
	MarkerEnd   = "# <<< EnvBox shell integration <<<"
)

// maxProfileBytes guards against pathological profile files.
const maxProfileBytes = 2 * 1024 * 1024

// Status describes the integration state. The JSON names are part of the UI
// contract: cmd/envbox/web reads shell.installed and shell.profilePath.
type Status struct {
	Installed         bool   `json:"installed"`
	ProfilePath       string `json:"profilePath"`
	ActivationPath    string `json:"activationPath"`
	HasActiveSnapshot bool   `json:"hasActiveSnapshot"`
	ShellName         string `json:"shellName"`
}

// Integration manages active.ps1 plus the managed block in $PROFILE.
type Integration struct {
	// Dir is the EnvBox config directory (defaults to the per-user config dir).
	Dir string
	// ProfilePath overrides the PowerShell profile location (tests, PowerShell 5 vs 7).
	ProfilePath string
}

// New returns the default integration.
func New() (*Integration, error) {
	dir, err := winsys.ConfigDir()
	if err != nil {
		return nil, err
	}
	return &Integration{Dir: dir}, nil
}

// ActivationPath is where the plaintext snapshot lives.
func (i *Integration) activationPath() string {
	dir := i.Dir
	if dir == "" {
		if resolved, err := winsys.ConfigDir(); err == nil {
			dir = resolved
		}
	}
	return filepath.Join(dir, "active.ps1")
}

// defaultProfilePath prefers PowerShell 7 (Documents\PowerShell) and falls back
// to Windows PowerShell 5.1 (Documents\WindowsPowerShell).
func defaultProfilePath() (string, string) {
	home := os.Getenv("USERPROFILE")
	if home == "" {
		return "", ""
	}
	pwsh7 := filepath.Join(home, "Documents", "PowerShell", "profile.ps1")
	if _, err := os.Stat(filepath.Join(home, "Documents", "PowerShell")); err == nil {
		return pwsh7, "pwsh"
	}
	return filepath.Join(home, "Documents", "WindowsPowerShell", "profile.ps1"), "Windows PowerShell"
}

// resolvedProfilePath returns the profile path and the shell name it belongs to.
func (i *Integration) resolvedProfilePath() (string, string) {
	if i.ProfilePath != "" {
		return i.ProfilePath, "PowerShell"
	}
	return defaultProfilePath()
}

// Status reports the current state.
func (i *Integration) Status() Status {
	profilePath, shellName := i.resolvedProfilePath()
	status := Status{
		ProfilePath:    profilePath,
		ActivationPath: i.activationPath(),
		ShellName:      shellName,
	}
	if data, err := os.ReadFile(profilePath); err == nil && len(data) <= maxProfileBytes {
		status.Installed = strings.Contains(string(data), MarkerStart)
	}
	if _, err := os.Stat(status.ActivationPath); err == nil {
		status.HasActiveSnapshot = true
	}
	return status
}

// WriteActivation overwrites active.ps1 with the profile's enabled variables.
func (i *Integration) WriteActivation(profile model.EnvProfile) error {
	var sb strings.Builder
	sb.WriteString("# EnvBox 激活快照 —— 由 EnvBox 生成，请勿手工编辑\n")
	sb.WriteString("# Generation: " + profile.Fingerprint()[:12] + "\n")
	sb.WriteString("# Updated: " + model.Now().Format("2006-01-02T15:04:05Z07:00") + "\n")
	for _, v := range profile.EnabledVariables() {
		sb.WriteString("$env:" + v.TrimmedKey() + " = " + quotePowerShell(v.Value) + "\n")
	}

	return fsx.WriteFileAtomic(i.activationPath(), []byte(sb.String()), 0o600)
}

// RemoveActivation deletes the snapshot; removing when absent is fine.
func (i *Integration) RemoveActivation() error {
	err := os.Remove(i.activationPath())
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	return nil
}

// Install adds the managed block to $PROFILE.
func (i *Integration) Install() error {
	profilePath, _ := i.resolvedProfilePath()
	if profilePath == "" {
		return errors.New("shell: 找不到用户目录，无法写入 PowerShell 配置")
	}
	existing, err := readProfile(profilePath)
	if err != nil {
		return err
	}
	if hasMalformedBlock(existing) {
		return errors.New("shell: $PROFILE 里的 EnvBox 标记不完整，已拒绝修改，请手工修复")
	}

	lines := removeBlock(existing)
	for len(lines) > 0 && strings.TrimSpace(lines[len(lines)-1]) == "" {
		lines = lines[:len(lines)-1]
	}
	if len(lines) > 0 {
		lines = append(lines, "")
	}
	snapshot := quotePowerShell(i.activationPath())
	lines = append(lines,
		MarkerStart,
		"if (Test-Path "+snapshot+") { . "+snapshot+" }",
		MarkerEnd,
	)

	if err := os.MkdirAll(filepath.Dir(profilePath), 0o700); err != nil {
		return err
	}
	return fsx.WriteFileAtomic(profilePath, []byte(strings.Join(lines, "\n")+"\n"), 0o600)
}

// Uninstall removes the managed block from $PROFILE.
func (i *Integration) Uninstall() error {
	profilePath, _ := i.resolvedProfilePath()
	if profilePath == "" {
		return nil
	}
	existing, err := readProfile(profilePath)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil
		}
		return err
	}
	if !strings.Contains(existing, MarkerStart) {
		return nil
	}
	if hasMalformedBlock(existing) {
		return errors.New("shell: $PROFILE 里的 EnvBox 标记不完整，已拒绝修改，请手工修复")
	}
	lines := removeBlock(existing)
	return fsx.WriteFileAtomic(profilePath, []byte(strings.Join(lines, "\n")), 0o600)
}

func readProfile(path string) (string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return "", nil
		}
		return "", err
	}
	if len(data) > maxProfileBytes {
		return "", fmt.Errorf("shell: $PROFILE 超过 %d 字节，拒绝修改", maxProfileBytes)
	}
	return string(data), nil
}

func hasMalformedBlock(content string) bool {
	return strings.Contains(content, MarkerStart) != strings.Contains(content, MarkerEnd)
}

// removeBlock drops everything between the markers, inclusive.
func removeBlock(content string) []string {
	lines := strings.Split(content, "\n")
	out := make([]string, 0, len(lines))
	skipping := false
	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		switch {
		case trimmed == MarkerStart:
			skipping = true
		case trimmed == MarkerEnd:
			skipping = false
		case skipping:
			// drop managed lines
		default:
			out = append(out, line)
		}
	}
	return out
}

// quotePowerShell renders a literal single-quoted string, doubling embedded quotes.
func quotePowerShell(value string) string {
	return "'" + strings.ReplaceAll(value, "'", "''") + "'"
}

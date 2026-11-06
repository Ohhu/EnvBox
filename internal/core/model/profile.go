// Package model mirrors the JSON shapes used by the macOS build so that
// .envbox files and vault payloads are interchangeable between platforms.
//
// 契约（改动会让 macOS 打不开 Windows 导出的文件）：
//   - 字段名与大小写完全一致；
//   - 时间是 ISO-8601 毫秒精度 UTC 字符串（见 Timestamp）；
//   - UUID 直接用字符串透传，不校验版本；
//   - []byte 按标准 base64 编码（Go 与 Swift 的 Data 编码一致）。
package model

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"sort"
	"strings"
)

// Schema versions and hard limits, mirrored from EnvBoxValidation.
const (
	CurrentSchemaVersion   = 1
	MaxProfiles            = 100
	MaxVariablesPerProfile = 500
	MaxKeyLength           = 128
	MaxValueBytes          = 32 * 1024
	MaxProfileValueBytes   = 512 * 1024
	MaxAggregateValueBytes = 8 * 1024 * 1024
	MaxVaultFileBytes      = 20 * 1024 * 1024
	MaxTotalVariables      = 5000
	MaxProfileNameLength   = 60
	MaxNoteLength          = 500
)

// EnvVariable is one editable environment entry inside a profile.
type EnvVariable struct {
	ID        string `json:"id"`
	Key       string `json:"key"`
	Value     string `json:"value"`
	IsEnabled bool   `json:"isEnabled"`
	IsSecret  bool   `json:"isSecret"`
	Note      string `json:"note"`
}

// TrimmedKey returns the key without surrounding whitespace.
func (v EnvVariable) TrimmedKey() string { return strings.TrimSpace(v.Key) }

// EnvProfile is one named set of variables.
type EnvProfile struct {
	ID        string        `json:"id"`
	Name      string        `json:"name"`
	Note      string        `json:"note"`
	Tint      string        `json:"tint"`
	Symbol    string        `json:"symbol"`
	Variables []EnvVariable `json:"variables"`
	CreatedAt Timestamp     `json:"createdAt"`
	UpdatedAt Timestamp     `json:"updatedAt"`
}

// EnabledVariables returns the variables that will be applied.
func (p EnvProfile) EnabledVariables() []EnvVariable {
	out := make([]EnvVariable, 0, len(p.Variables))
	for _, v := range p.Variables {
		if v.IsEnabled {
			out = append(out, v)
		}
	}
	return out
}

// SecretCount counts variables flagged as sensitive.
func (p EnvProfile) SecretCount() int {
	n := 0
	for _, v := range p.Variables {
		if v.IsSecret {
			n++
		}
	}
	return n
}

// Normalized trims user input the same way the macOS build does.
func (p EnvProfile) Normalized() EnvProfile {
	out := p
	out.Name = strings.TrimSpace(p.Name)
	out.Note = truncateRunes(strings.TrimSpace(p.Note), MaxNoteLength)
	if out.Symbol == "" {
		out.Symbol = "shippingbox.fill"
	}
	if out.Tint == "" {
		out.Tint = "aurora"
	}
	vars := make([]EnvVariable, 0, len(p.Variables))
	for _, v := range p.Variables {
		item := v
		item.Key = v.TrimmedKey()
		item.Note = truncateRunes(strings.TrimSpace(v.Note), MaxNoteLength)
		vars = append(vars, item)
	}
	out.Variables = vars
	return out
}

// Fingerprint is a stable, non-reversible digest of the enabled environment.
// It must stay byte-identical to the macOS implementation so that both
// platforms agree on whether the applied environment is up to date.
func (p EnvProfile) Fingerprint() string {
	enabled := p.EnabledVariables()
	sort.Slice(enabled, func(i, j int) bool {
		return enabled[i].TrimmedKey() < enabled[j].TrimmedKey()
	})
	var sb strings.Builder
	sb.WriteString("EnvBoxProfileV1\n")
	for _, v := range enabled {
		key := v.TrimmedKey()
		fmt.Fprintf(&sb, "%d:%s=%d:%s\n", len(key), key, len(v.Value), v.Value)
	}
	sum := sha256.Sum256([]byte(sb.String()))
	return hex.EncodeToString(sum[:])
}

// AppSettings mirrors the macOS settings block. Only the fields needed for
// round-tripping are modelled; unknown future keys are preserved by keeping the
// raw document when we cannot decode it.
type AppSettings struct {
	AutoRestoreActiveProfile     bool `json:"autoRestoreActiveProfile"`
	IncludeLoginShellEnvironment bool `json:"includeLoginShellEnvironment"`
	ShowInternalVariables        bool `json:"showInternalVariables"`
	ConcealSensitiveValues       bool `json:"concealSensitiveValues"`
	AutoClearSensitiveClipboard  bool `json:"autoClearSensitiveClipboard"`
	HasCompletedFirstApply       bool `json:"hasCompletedFirstApply"`
	ShellIntegrationEnabled      bool `json:"shellIntegrationEnabled"`
	MCPEnabled                   bool `json:"mcpEnabled"`
	MCPAllowReveal               bool `json:"mcpAllowReveal"`
	LaunchAtLogin                bool `json:"launchAtLogin"`
	HasAcknowledgedRestartHint   bool `json:"hasAcknowledgedRestartHint"`
}

// DefaultAppSettings returns the macOS defaults.
func DefaultAppSettings() AppSettings {
	return AppSettings{
		AutoRestoreActiveProfile:     true,
		IncludeLoginShellEnvironment: true,
		ConcealSensitiveValues:       true,
		AutoClearSensitiveClipboard:  true,
		LaunchAtLogin:                true,
	}
}

// VaultPayload is the plaintext inside the encrypted local vault.
type VaultPayload struct {
	SchemaVersion      int          `json:"schemaVersion"`
	Profiles           []EnvProfile `json:"profiles"`
	ActiveProfileID    *string      `json:"activeProfileID"`
	AppliedKeys        []string     `json:"appliedKeys"`
	AppliedFingerprint *string      `json:"appliedFingerprint"`
	Settings           AppSettings  `json:"settings"`
	CreatedAt          Timestamp    `json:"createdAt"`
	UpdatedAt          Timestamp    `json:"updatedAt"`
}

// EmptyVaultPayload builds a fresh payload.
func EmptyVaultPayload(now Timestamp) *VaultPayload {
	return &VaultPayload{
		SchemaVersion: CurrentSchemaVersion,
		Profiles:      []EnvProfile{},
		AppliedKeys:   []string{},
		Settings:      DefaultAppSettings(),
		CreatedAt:     now,
		UpdatedAt:     now,
	}
}

// ActiveProfile returns the active profile, if any.
func (p *VaultPayload) ActiveProfile() *EnvProfile {
	if p.ActiveProfileID == nil {
		return nil
	}
	for i := range p.Profiles {
		if p.Profiles[i].ID == *p.ActiveProfileID {
			return &p.Profiles[i]
		}
	}
	return nil
}

// PortableConfiguration is the plaintext inside an exported .envbox file.
type PortableConfiguration struct {
	SchemaVersion int          `json:"schemaVersion"`
	Profiles      []EnvProfile `json:"profiles"`
	ExportedAt    Timestamp    `json:"exportedAt"`
	Generator     string       `json:"generator"`
}

// VaultEnvelope is the ciphertext wrapper written to disk.
type VaultEnvelope struct {
	Format  string `json:"format"`
	Version int    `json:"version"`
	KeyID   string `json:"keyID"`
	Sealed  []byte `json:"sealed"`
}

// ExportEnvelope wraps an encrypted .envbox file.
type ExportEnvelope struct {
	Format     string    `json:"format"`
	Version    int       `json:"version"`
	CreatedAt  Timestamp `json:"createdAt"`
	KDF        string    `json:"kdf"`
	Iterations int       `json:"iterations"`
	Salt       []byte    `json:"salt"`
	Sealed     []byte    `json:"sealed"`
}

// Format identifiers shared with the macOS build.
const (
	VaultFormat            = "envbox.vault"
	ExportFormat           = "envbox.export"
	ExportKDF              = "PBKDF2-HMAC-SHA256"
	CurrentEnvelopeVersion = 1
)

// IsValidKey reports whether key is a syntactically valid variable name.
func IsValidKey(key string) bool {
	if key == "" || len(key) > MaxKeyLength {
		return false
	}
	for i, r := range key {
		isUpper := r >= 'A' && r <= 'Z'
		isLower := r >= 'a' && r <= 'z'
		isDigit := r >= '0' && r <= '9'
		if i == 0 {
			if r != '_' && !isUpper && !isLower {
				return false
			}
			continue
		}
		if !isUpper && !isLower && !isDigit && r != '_' {
			return false
		}
	}
	return true
}

// ValidateProfile enforces the same constraints as the macOS build.
func ValidateProfile(p EnvProfile) error {
	n := p.Normalized()
	if n.Name == "" {
		return errors.New("model: 配置名不能为空")
	}
	if len([]rune(n.Name)) > MaxProfileNameLength {
		return errors.New("model: 配置名过长")
	}
	if len([]rune(n.Note)) > MaxNoteLength {
		return fmt.Errorf("model: 备注过长（%s）", n.Name)
	}
	if len(n.Variables) > MaxVariablesPerProfile {
		return fmt.Errorf("model: 变量数量超过上限（%s）", n.Name)
	}
	seen := make(map[string]struct{}, len(n.Variables))
	ids := make(map[string]struct{}, len(n.Variables))
	total := 0
	for _, v := range n.Variables {
		if _, dup := ids[v.ID]; dup {
			return errors.New("model: 变量 ID 重复")
		}
		ids[v.ID] = struct{}{}
		key := v.TrimmedKey()
		if !IsValidKey(key) {
			return fmt.Errorf("model: 变量名不合法：%q", key)
		}
		if len(v.Value) > MaxValueBytes {
			return fmt.Errorf("model: 变量值过大：%s", key)
		}
		if strings.ContainsRune(v.Value, 0) {
			return fmt.Errorf("model: 变量值包含 NUL：%s", key)
		}
		if _, dup := seen[strings.ToUpper(key)]; dup {
			return fmt.Errorf("model: 变量名重复：%s", key)
		}
		seen[strings.ToUpper(key)] = struct{}{}
		total += len(v.Value)
		if total > MaxProfileValueBytes {
			return fmt.Errorf("model: 配置体积过大：%s", n.Name)
		}
	}
	return nil
}

// ValidateProfiles checks a profile list. Name uniqueness is optional because it
// must not be enforced when reading an existing vault: a store written by an
// older build with duplicate names must still open.
func ValidateProfiles(profiles []EnvProfile, requireUniqueNames bool) error {
	if len(profiles) > MaxProfiles {
		return errors.New("model: 配置数量超过上限")
	}
	ids := make(map[string]struct{}, len(profiles))
	names := make(map[string]struct{}, len(profiles))
	totalVars, totalBytes := 0, 0
	for _, profile := range profiles {
		if _, dup := ids[profile.ID]; dup {
			return errors.New("model: 配置 ID 重复")
		}
		ids[profile.ID] = struct{}{}
		if err := ValidateProfile(profile); err != nil {
			return err
		}
		if requireUniqueNames {
			name := strings.ToLower(profile.Normalized().Name)
			if _, dup := names[name]; dup {
				return fmt.Errorf("model: 配置名重复：%s", name)
			}
			names[name] = struct{}{}
		}
		totalVars += len(profile.Variables)
		for _, v := range profile.Variables {
			totalBytes += len(v.Value)
		}
		if totalBytes > MaxAggregateValueBytes {
			return errors.New("model: 配置库体积超过上限")
		}
	}
	if totalVars > MaxTotalVariables {
		return errors.New("model: 变量总数超过上限")
	}
	return nil
}

// ValidateUniqueNames rejects duplicate profile names; use it when writing.
func ValidateUniqueNames(profiles []EnvProfile) error {
	names := make(map[string]struct{}, len(profiles))
	for _, profile := range profiles {
		name := strings.ToLower(profile.Normalized().Name)
		if _, dup := names[name]; dup {
			return fmt.Errorf("model: 配置名重复：%s", name)
		}
		names[name] = struct{}{}
	}
	return nil
}

// ValidatePayload enforces the vault level constraints.
func ValidatePayload(p *VaultPayload) error {
	if p.SchemaVersion > CurrentSchemaVersion {
		return fmt.Errorf("model: 不支持的配置库版本 %d", p.SchemaVersion)
	}
	if err := ValidateProfiles(p.Profiles, false); err != nil {
		return err
	}
	ids := make(map[string]struct{}, len(p.Profiles))
	for _, profile := range p.Profiles {
		ids[profile.ID] = struct{}{}
	}
	if p.ActiveProfileID != nil {
		if _, ok := ids[*p.ActiveProfileID]; !ok {
			return errors.New("model: 激活的配置不存在")
		}
	}
	for _, key := range p.AppliedKeys {
		if !IsValidKey(key) {
			return fmt.Errorf("model: 已应用变量名不合法：%q", key)
		}
	}
	return nil
}

func truncateRunes(s string, max int) string {
	r := []rune(s)
	if len(r) <= max {
		return s
	}
	return string(r[:max])
}

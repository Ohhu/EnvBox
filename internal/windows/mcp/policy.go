//go:build windows

package mcp

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"

	"github.com/Ohhu/EnvBox/internal/windows/fsx"
	"github.com/Ohhu/EnvBox/internal/windows/winsys"
)

// Policy is the on-disk switch the app owns. The helper only reads it, and
// re-reads it on every call so disabling MCP in the settings takes effect
// immediately without restarting the client.
type Policy struct {
	Enabled     bool `json:"enabled"`
	AllowReveal bool `json:"allowReveal"`
}

// PolicyFileName lives next to the vault: %LOCALAPPDATA%\EnvBox\mcp.json.
const PolicyFileName = "mcp.json"

// PolicyPath returns the policy file location.
func PolicyPath() (string, error) {
	dir, err := winsys.ConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, PolicyFileName), nil
}

// LoadPolicy reads the policy; a missing or malformed file means "disabled".
func LoadPolicy() Policy {
	path, err := PolicyPath()
	if err != nil {
		return Policy{}
	}
	raw, err := os.ReadFile(path)
	if err != nil || len(raw) > 64*1024 {
		return Policy{}
	}
	var policy Policy
	if err := json.Unmarshal(raw, &policy); err != nil {
		return Policy{}
	}
	return policy
}

// SavePolicy writes the policy atomically with owner-only permissions.
func SavePolicy(policy Policy) error {
	path, err := PolicyPath()
	if err != nil {
		return err
	}
	if _, err := winsys.EnsureConfigDir(); err != nil {
		return err
	}
	encoded, err := json.MarshalIndent(policy, "", "  ")
	if err != nil {
		return err
	}
	return fsx.WriteFileAtomic(path, encoded, 0o600)
}

// ErrDisabled is returned when a tool is called while MCP is switched off.
var ErrDisabled = errors.New("MCP 已在 EnvBox 设置中关闭")

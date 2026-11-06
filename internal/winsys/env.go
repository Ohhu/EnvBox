//go:build windows

package winsys

import (
	"fmt"
	"os"
	"sort"
	"strings"
	"syscall"

	"github.com/Ohhu/EnvBox/internal/buildinfo"
	"github.com/Ohhu/EnvBox/internal/model"
)

// EnvKeyPath is the per-user environment key. Machine-wide variables live under
// HKLM and are intentionally out of scope: writing them needs administrator rights.
const EnvKeyPath = `Environment`

// EnvEntry is one environment value with its registry type preserved.
type EnvEntry struct {
	Name     string
	Value    string
	Expanded string
	Type     uint32
}

// EnvStore reads and writes one environment registry key.
type EnvStore struct {
	// KeyPath defaults to EnvKeyPath; tests point it at a sandbox key.
	KeyPath string
}

// NewUserEnvStore targets HKCU\Environment.
func NewUserEnvStore() *EnvStore { return &EnvStore{KeyPath: EnvKeyPath} }

// List returns every value of the key, sorted by name.
func (s *EnvStore) List() ([]EnvEntry, error) {
	key, err := OpenUserKey(s.path())
	if err != nil {
		return nil, err
	}
	defer key.Close()

	values, err := key.Values()
	if err != nil {
		return nil, err
	}
	entries := make([]EnvEntry, 0, len(values))
	for _, v := range values {
		entry := EnvEntry{Name: v.Name, Type: v.Type}
		switch v.Type {
		case RegSZ, RegExpandSZ:
			entry.Value = decodeUTF16(v.Data)
			if v.Type == RegExpandSZ {
				entry.Expanded = ExpandEnvironment(entry.Value)
			} else {
				entry.Expanded = entry.Value
			}
		default:
			// REG_DWORD / REG_BINARY / REG_MULTI_SZ are not environment variables;
			// keep them listed but empty so we never delete them by accident.
			entry.Expanded = ""
		}
		entries = append(entries, entry)
	}
	sort.Slice(entries, func(i, j int) bool {
		return strings.ToUpper(entries[i].Name) < strings.ToUpper(entries[j].Name)
	})
	return entries, nil
}

// Remove deletes the named variables, case-insensitively, and reports which ones existed.
func (s *EnvStore) Remove(names []string) ([]string, error) {
	key, err := CreateUserKey(s.path())
	if err != nil {
		return nil, err
	}
	defer key.Close()

	existing, err := s.List()
	if err != nil {
		return nil, err
	}
	spelling := make(map[string]string, len(existing))
	for _, entry := range existing {
		spelling[strings.ToUpper(entry.Name)] = entry.Name
	}

	removed := make([]string, 0, len(names))
	for _, name := range names {
		upper := strings.ToUpper(strings.TrimSpace(name))
		if upper == "" {
			continue
		}
		actual, ok := spelling[upper]
		if !ok {
			continue
		}
		if err := key.DeleteValue(actual); err != nil {
			return removed, err
		}
		removed = append(removed, actual)
	}
	sort.Strings(removed)
	return removed, nil
}

// EnvKeyEnv relocates the environment key for development builds, so E2E runs do
// not touch the real HKCU\Environment. Ignored by production builds.
const EnvKeyEnv = "ENVBOX_ENV_KEY"

// NewConfigurableEnvStore returns the real user environment store, or the path
// from ENVBOX_ENV_KEY in development builds.
func NewConfigurableEnvStore() *EnvStore {
	if override := os.Getenv(EnvKeyEnv); override != "" && buildinfo.Channel != "production" {
		return &EnvStore{KeyPath: override}
	}
	return NewUserEnvStore()
}

// ApplyReport describes what Apply changed.
type ApplyReport struct {
	Applied  []string
	Stale    []string
	Warnings []string
}

// Apply writes the profile's enabled variables and removes keys that the
// previously applied profile owned but this one no longer defines.
//
// Windows semantics handled here:
//   - names are case-insensitive, so the existing spelling is reused;
//   - an empty string is a defined-but-empty variable, distinct from missing;
//   - REG_EXPAND_SZ is preserved instead of being frozen into REG_SZ.
func (s *EnvStore) Apply(profile model.EnvProfile, previouslyApplied []string) (ApplyReport, error) {
	normalized := profile.Normalized()
	if err := model.ValidateProfile(normalized); err != nil {
		return ApplyReport{}, err
	}

	enabled := normalized.EnabledVariables()
	sort.Slice(enabled, func(i, j int) bool {
		return strings.ToUpper(enabled[i].TrimmedKey()) < strings.ToUpper(enabled[j].TrimmedKey())
	})

	report := ApplyReport{}
	desired := make(map[string]model.EnvVariable, len(enabled))
	for _, v := range enabled {
		key := v.TrimmedKey()
		upper := strings.ToUpper(key)
		if other, dup := desired[upper]; dup {
			return report, fmt.Errorf("winsys: 变量名重复（Windows 不区分大小写）：%s 与 %s", other.TrimmedKey(), key)
		}
		desired[upper] = v
	}

	key, err := CreateUserKey(s.path())
	if err != nil {
		return report, err
	}
	defer key.Close()

	existing, err := s.List()
	if err != nil {
		return report, err
	}
	spelling := make(map[string]string, len(existing))
	for _, entry := range existing {
		spelling[strings.ToUpper(entry.Name)] = entry.Name
	}

	for upper, variable := range desired {
		name := spelling[upper]
		if name == "" {
			name = variable.TrimmedKey()
		} else if name != variable.TrimmedKey() {
			// Windows ignores case, so the existing spelling wins; say so instead of
			// silently rewriting the name the user typed.
			report.Warnings = append(report.Warnings, fmt.Sprintf("%s 已按注册表里的拼写 %s 写入", variable.TrimmedKey(), name))
		}
		if err := key.SetString(name, variable.Value, valueTypeFor(existing, upper, variable.Value)); err != nil {
			return report, err
		}
		report.Applied = append(report.Applied, name)
	}
	sort.Strings(report.Applied)

	for _, name := range previouslyApplied {
		if _, keep := desired[strings.ToUpper(strings.TrimSpace(name))]; keep {
			continue
		}
		if _, exists := spelling[strings.ToUpper(name)]; !exists {
			continue
		}
		if err := key.DeleteValue(spelling[strings.ToUpper(name)]); err != nil {
			if IsAccessDenied(err) {
				report.Warnings = append(report.Warnings, fmt.Sprintf("无权限删除残留变量 %s，请手动清理", name))
				continue
			}
			return report, err
		}
		report.Stale = append(report.Stale, name)
	}
	sort.Strings(report.Stale)
	return report, nil
}

func valueTypeFor(existing []EnvEntry, upper, value string) uint32 {
	for _, entry := range existing {
		if strings.ToUpper(entry.Name) == upper {
			if entry.Type == RegExpandSZ && strings.ContainsRune(value, '%') {
				return RegExpandSZ
			}
			return RegSZ
		}
	}
	return RegSZ
}

func (s *EnvStore) path() string {
	if s.KeyPath == "" {
		return EnvKeyPath
	}
	return s.KeyPath
}

func decodeUTF16(data []byte) string {
	if len(data) == 0 {
		return ""
	}
	chars := make([]uint16, 0, len(data)/2)
	for i := 0; i+1 < len(data); i += 2 {
		unit := uint16(data[i]) | uint16(data[i+1])<<8
		if unit == 0 {
			break
		}
		chars = append(chars, unit)
	}
	return syscall.UTF16ToString(chars)
}

//go:build windows

// Package settings stores non-secret user preferences next to the vault.
//
// Values live in the encrypted vault; this file only records switches such as
// "check for updates daily" plus the updater's cache bookkeeping.
package settings

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/Ohhu/EnvBox/internal/windows/fsx"
	"github.com/Ohhu/EnvBox/internal/windows/winsys"
)

// FileName is the settings document inside the config directory.
const FileName = "settings.json"

// UpdateCheck is how often the updater may run on its own.
type UpdateCheck string

// Allowed check frequencies.
const (
	CheckOff    UpdateCheck = "off"
	CheckDaily  UpdateCheck = "daily"
	CheckWeekly UpdateCheck = "weekly"
)

// Update is the updater section of the settings file.
type Update struct {
	Check          UpdateCheck `json:"check"`
	SkippedVersion string      `json:"skippedVersion,omitempty"`
	ETag           string      `json:"etag,omitempty"`
	LastCheckAt    string      `json:"lastCheckAt,omitempty"`
	LastResult     string      `json:"lastResult,omitempty"`
}

// Settings is the whole document.
type Settings struct {
	Update Update `json:"update"`
}

// Default returns the shipped defaults: check daily, never install silently.
func Default() Settings {
	return Settings{Update: Update{Check: CheckDaily}}
}

// Path returns the settings file location.
func Path() (string, error) {
	dir, err := winsys.ConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, FileName), nil
}

// Mutate applies fn to the current settings under a process-wide lock, so the
// background update check and the settings page cannot overwrite each other with
// stale snapshots.
func Mutate(fn func(*Settings) error) error {
	fileMu.Lock()
	defer fileMu.Unlock()
	current := Load()
	if err := fn(&current); err != nil {
		return err
	}
	return current.Save()
}

// Load reads the settings, falling back to defaults for anything missing.
func Load() Settings {
	filePath, err := Path()
	if err != nil {
		return Default()
	}
	raw, err := os.ReadFile(filePath)
	if err != nil {
		return Default()
	}
	loaded := Default()
	if err := json.Unmarshal(raw, &loaded); err != nil {
		return Default()
	}
	loaded.normalize()
	return loaded
}

// NormalizeCheck maps an arbitrary string to a supported frequency, defaulting to
// daily. Unknown values never disable checking by accident.
func NormalizeCheck(value string) UpdateCheck {
	switch UpdateCheck(value) {
	case CheckOff:
		return CheckOff
	case CheckWeekly:
		return CheckWeekly
	default:
		return CheckDaily
	}
}

func (s *Settings) normalize() {
	switch s.Update.Check {
	case CheckOff, CheckDaily, CheckWeekly:
	default:
		s.Update.Check = CheckDaily
	}
}

// Save writes the settings atomically.
func (s Settings) Save() error {
	if _, err := winsys.EnsureConfigDir(); err != nil {
		return err
	}
	filePath, err := Path()
	if err != nil {
		return err
	}
	s.normalize()
	encoded, err := json.MarshalIndent(s, "", "  ")
	if err != nil {
		return err
	}
	return fsx.WriteFileAtomic(filePath, encoded, 0o600)
}

// DueForCheck reports whether an automatic check should run now.
func (u Update) DueForCheck(now time.Time) bool {
	switch u.Check {
	case CheckOff:
		return false
	case CheckWeekly:
		last, ok := u.lastCheck()
		return !ok || now.Sub(last) >= 7*24*time.Hour
	default:
		last, ok := u.lastCheck()
		return !ok || now.Sub(last) >= 24*time.Hour
	}
}

func (u Update) lastCheck() (time.Time, bool) {
	if u.LastCheckAt == "" {
		return time.Time{}, false
	}
	parsed, err := time.Parse(time.RFC3339, u.LastCheckAt)
	if err != nil {
		return time.Time{}, false
	}
	return parsed, true
}

// MarkChecked records a completed check.
func (u *Update) MarkChecked(now time.Time, result string) {
	u.LastCheckAt = now.UTC().Format(time.RFC3339)
	u.LastResult = result
}

// ErrDisabled is returned when automatic checking is switched off.
var ErrDisabled = errors.New("settings: 更新检查已关闭")

// fileMu serialises read-modify-write cycles on settings.json.
var fileMu sync.Mutex

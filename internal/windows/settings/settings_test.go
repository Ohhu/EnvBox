//go:build windows

package settings

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func withConfigDir(t *testing.T) {
	t.Helper()
	t.Setenv("ENVBOX_CONFIG_DIR", filepath.Join(t.TempDir(), "config"))
}

func TestLoadReturnsDefaultsWhenMissing(t *testing.T) {
	withConfigDir(t)
	got := Load()
	if got.Update.Check != CheckDaily {
		t.Fatalf("unexpected defaults: %+v", got.Update)
	}
}

func TestSaveLoadRoundTrip(t *testing.T) {
	withConfigDir(t)
	changed := Default()
	changed.Update.SkippedVersion = "1.2.0"
	changed.Update.MarkChecked(time.Date(2026, 11, 2, 4, 0, 0, 0, time.UTC), "no-update")
	if err := changed.Save(); err != nil {
		t.Fatalf("save: %v", err)
	}

	loaded := Load()
	if loaded.Update.Check != CheckDaily || loaded.Update.SkippedVersion != "1.2.0" {
		t.Fatalf("round trip mismatch: %+v", loaded.Update)
	}
	if loaded.Update.LastResult != "no-update" {
		t.Fatalf("last result lost: %+v", loaded.Update)
	}
	if _, err := os.Stat(filepath.Join(os.Getenv("ENVBOX_CONFIG_DIR"), FileName)); err != nil {
		t.Fatalf("settings file missing: %v", err)
	}
}

func TestMutateSerialisesUpdates(t *testing.T) {
	withConfigDir(t)
	if err := Mutate(func(current *Settings) error {
		current.Update.SkippedVersion = "2.0.0"
		return nil
	}); err != nil {
		t.Fatalf("mutate: %v", err)
	}
	if got := Load().Update.SkippedVersion; got != "2.0.0" {
		t.Fatalf("mutate did not persist: %q", got)
	}
}

func TestDueForCheck(t *testing.T) {
	now := time.Date(2026, 11, 2, 12, 0, 0, 0, time.UTC)
	update := Update{Check: CheckDaily}
	if !update.DueForCheck(now) {
		t.Fatal("never checked should be due")
	}
	update.MarkChecked(now.Add(-time.Hour), "up-to-date")
	if update.DueForCheck(now) {
		t.Fatal("checked an hour ago should not be due")
	}
	update.MarkChecked(now.Add(-25*time.Hour), "up-to-date")
	if !update.DueForCheck(now) {
		t.Fatal("daily check overdue")
	}
	update.Check = CheckOff
	if update.DueForCheck(now.Add(72 * time.Hour)) {
		t.Fatal("off must never be due")
	}
}

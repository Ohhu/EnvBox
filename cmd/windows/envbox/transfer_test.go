//go:build windows

package main

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/Ohhu/EnvBox/internal/core/model"
	"github.com/Ohhu/EnvBox/internal/core/portable"
)

func TestDuplicateProfileCopiesWithFreshIds(t *testing.T) {
	app := newTestApp(t)
	result, err := app.Dispatch("duplicate-profile", mustJSON(t, map[string]any{"id": "p1"}))
	if err != nil {
		t.Fatalf("dispatch: %v", err)
	}
	if !result.OK {
		t.Fatalf("duplicate failed: %s", result.Message)
	}

	payload, err := app.store.Load()
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	if len(payload.Profiles) != 2 {
		t.Fatalf("expected 2 profiles, got %d", len(payload.Profiles))
	}
	copied := payload.Profiles[1]
	if copied.Name != "工作 副本" {
		t.Fatalf("unexpected name %q", copied.Name)
	}
	if copied.ID == "p1" {
		t.Fatal("copy must get its own id")
	}
	if result.Focus != copied.ID {
		t.Fatalf("focus %q must point at the copy", result.Focus)
	}
	if len(copied.Variables) != 2 {
		t.Fatalf("variables not copied: %d", len(copied.Variables))
	}
	sourceSeen := map[string]struct{}{"v1": {}, "v2": {}}
	for _, variable := range copied.Variables {
		if _, clash := sourceSeen[variable.ID]; clash {
			t.Fatalf("variable id %q was reused", variable.ID)
		}
	}
	if copied.Variables[0].Value != "real-secret" {
		t.Fatalf("secret not carried over: %q", copied.Variables[0].Value)
	}
}

func TestDuplicateProfileNumbersRepeatedCopies(t *testing.T) {
	app := newTestApp(t)
	for i := 0; i < 2; i++ {
		if _, err := app.Dispatch("duplicate-profile", mustJSON(t, map[string]any{"id": "p1"})); err != nil {
			t.Fatalf("dispatch: %v", err)
		}
	}
	payload, err := app.store.Load()
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	names := []string{}
	for _, profile := range payload.Profiles {
		names = append(names, profile.Name)
	}
	want := []string{"工作", "工作 副本", "工作 副本 2"}
	for i := range want {
		if i >= len(names) || names[i] != want[i] {
			t.Fatalf("names = %v, want %v", names, want)
		}
	}
}

func TestImportRenamesCollisionsAndKeepsBoth(t *testing.T) {
	app := newTestApp(t)
	archive := writeArchive(t, []model.EnvProfile{{
		ID:   "p1", // same id as the local profile on purpose
		Name: "工作",
		Variables: []model.EnvVariable{
			{ID: "x1", Key: "FROM_ARCHIVE", Value: "yes", IsEnabled: true},
		},
	}})
	app.dialog = func() (string, error) { return archive, nil }

	pick, err := app.Dispatch("import-pick", "")
	if err != nil {
		t.Fatalf("pick: %v", err)
	}
	if !pick.OK || pick.Pick == nil {
		t.Fatalf("pick returned %+v", pick)
	}
	if pick.Pick.Name != filepath.Base(archive) || pick.Pick.Bytes <= 0 {
		t.Fatalf("unexpected pick %+v", pick.Pick)
	}

	result, err := app.Dispatch("import", mustJSON(t, map[string]any{"passphrase": "password123"}))
	if err != nil {
		t.Fatalf("import: %v", err)
	}
	if !result.OK {
		t.Fatalf("import failed: %s", result.Message)
	}

	payload, err := app.store.Load()
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	if len(payload.Profiles) != 2 {
		t.Fatalf("expected 2 profiles, got %d", len(payload.Profiles))
	}
	imported := payload.Profiles[1]
	if imported.Name != "工作 2" {
		t.Fatalf("name clash must be renamed, got %q", imported.Name)
	}
	if imported.ID == "p1" {
		t.Fatal("id clash must be re-keyed")
	}
	if imported.Variables[0].ID != "" && imported.Variables[0].ID == "x1" {
		t.Fatal("imported variable id must be regenerated")
	}
	if result.Focus != imported.ID {
		t.Fatalf("focus %q must point at the imported profile", result.Focus)
	}
	// The local profile must be untouched.
	if payload.Profiles[0].ID != "p1" || payload.Profiles[0].Name != "工作" {
		t.Fatalf("local profile changed: %+v", payload.Profiles[0])
	}
}

func TestImportNeedsAPickedFile(t *testing.T) {
	app := newTestApp(t)
	result, err := app.Dispatch("import", mustJSON(t, map[string]any{"passphrase": "password123"}))
	if err != nil {
		t.Fatalf("dispatch: %v", err)
	}
	if result.OK {
		t.Fatal("import without a picked file must fail")
	}
}

func TestImportRejectsStalePick(t *testing.T) {
	app := newTestApp(t)
	archive := writeArchive(t, []model.EnvProfile{{ID: "a1", Name: "归档"}})
	app.pendingImport = archive
	app.pendingImportAt = time.Now().Add(-2 * importPendingTTL)

	result, err := app.Dispatch("import", mustJSON(t, map[string]any{"passphrase": "password123"}))
	if err != nil {
		t.Fatalf("dispatch: %v", err)
	}
	if result.OK {
		t.Fatal("a stale pick must be refused")
	}
	payload, err := app.store.Load()
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	if len(payload.Profiles) != 1 {
		t.Fatalf("stale import wrote profiles: %d", len(payload.Profiles))
	}
}

func TestPickImportWithoutDialogExplainsTheCLI(t *testing.T) {
	app := newTestApp(t)
	result, err := app.Dispatch("import-pick", "")
	if err != nil {
		t.Fatalf("dispatch: %v", err)
	}
	if result.OK {
		t.Fatal("no dialog must be reported, not faked")
	}
	if result.Message == "" {
		t.Fatal("the failure must tell the user what to do instead")
	}
}

func TestUniqueProfileNameKeepsNamesFree(t *testing.T) {
	existing := []model.EnvProfile{{Name: "Prod"}, {Name: "prod 2"}}
	if got := uniqueProfileName("prod", existing); got != "prod 3" {
		t.Fatalf("got %q", got)
	}
	if got := uniqueProfileName("  ", existing); got != "未命名配置" {
		t.Fatalf("got %q", got)
	}
}

// writeArchive exports profiles into a temp .envbox file and returns its path.
func writeArchive(t *testing.T, profiles []model.EnvProfile) string {
	t.Helper()
	blob, err := portable.Export(profiles, "password123", 0, model.Now())
	if err != nil {
		t.Fatalf("export: %v", err)
	}
	path := filepath.Join(t.TempDir(), "import.envbox")
	if err := os.WriteFile(path, blob, 0o600); err != nil {
		t.Fatalf("write: %v", err)
	}
	return path
}

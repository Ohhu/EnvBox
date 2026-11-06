//go:build windows

package main

import (
	"path/filepath"
	"testing"

	"github.com/Ohhu/EnvBox/internal/core/model"
	"github.com/Ohhu/EnvBox/internal/windows/shell"
	"github.com/Ohhu/EnvBox/internal/windows/vault"
	"github.com/Ohhu/EnvBox/internal/windows/winsys"
)

func newTestApp(t *testing.T) *App {
	t.Helper()
	dir := t.TempDir()
	store := &vault.Store{Path: filepath.Join(dir, "vault.envbox"), Provider: &vault.MemoryProvider{ID: "k"}}
	payload := model.EmptyVaultPayload(model.Now())
	payload.Profiles = []model.EnvProfile{{
		ID: "p1", Name: "工作",
		Variables: []model.EnvVariable{
			{ID: "v1", Key: "API_TOKEN", Value: "real-secret", IsEnabled: true, IsSecret: true},
			{ID: "v2", Key: "REGION", Value: "cn", IsEnabled: true},
		},
	}}
	if err := store.Save(payload); err != nil {
		t.Fatalf("seed: %v", err)
	}
	return &App{
		store: store,
		env:   &winsys.EnvStore{KeyPath: `Software\EnvBoxTest\Environment`},
		shell: &shell.Integration{Dir: dir, ProfilePath: filepath.Join(dir, "profile.ps1")},
	}
}

func TestSaveProfileKeepsMaskedSecret(t *testing.T) {
	app := newTestApp(t)
	state, err := app.State()
	if err != nil {
		t.Fatalf("state: %v", err)
	}
	if len(state.Profiles) != 1 {
		t.Fatalf("unexpected profiles %+v", state.Profiles)
	}

	// This is exactly what the editor posts back: the list view object with the
	// secret replaced by bullets.
	view := state.Profiles[0]
	view.Name = "工作（改名）"
	if _, err := app.Dispatch("save-profile", mustJSON(t, map[string]any{"profile": view})); err != nil {
		t.Fatalf("dispatch: %v", err)
	}

	payload, err := app.store.Load()
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	stored := payload.Profiles[0]
	if stored.Name != "工作（改名）" {
		t.Fatalf("name not saved: %q", stored.Name)
	}
	for _, variable := range stored.Variables {
		if variable.Key == "API_TOKEN" && variable.Value != "real-secret" {
			t.Fatalf("secret was overwritten with %q", variable.Value)
		}
	}
}

func TestSaveProfileAcceptsNewSecretValue(t *testing.T) {
	app := newTestApp(t)
	state, err := app.State()
	if err != nil {
		t.Fatal(err)
	}
	view := state.Profiles[0]
	for i := range view.Variables {
		if view.Variables[i].Key == "API_TOKEN" {
			view.Variables[i].Value = "rotated-secret"
		}
	}
	if _, err := app.Dispatch("save-profile", mustJSON(t, map[string]any{"profile": view})); err != nil {
		t.Fatalf("dispatch: %v", err)
	}
	payload, err := app.store.Load()
	if err != nil {
		t.Fatal(err)
	}
	for _, variable := range payload.Profiles[0].Variables {
		if variable.Key == "API_TOKEN" && variable.Value != "rotated-secret" {
			t.Fatalf("new value not stored: %q", variable.Value)
		}
	}
}

func TestSaveProfileRestoresMaskedValueAfterUnflagging(t *testing.T) {
	app := newTestApp(t)
	state, err := app.State()
	if err != nil {
		t.Fatal(err)
	}
	view := state.Profiles[0]
	for i := range view.Variables {
		if view.Variables[i].Key == "API_TOKEN" {
			view.Variables[i].Secret = false // user cleared the secret checkbox
		}
	}
	if _, err := app.Dispatch("save-profile", mustJSON(t, map[string]any{"profile": view})); err != nil {
		t.Fatalf("dispatch: %v", err)
	}
	payload, err := app.store.Load()
	if err != nil {
		t.Fatal(err)
	}
	for _, variable := range payload.Profiles[0].Variables {
		if variable.Key == "API_TOKEN" && variable.Value != "real-secret" {
			t.Fatalf("取消 secret 勾选后原值被 %q 覆盖", variable.Value)
		}
	}
}

func TestSaveProfileRejectsUnknownMaskedValue(t *testing.T) {
	app := newTestApp(t)
	state, err := app.State()
	if err != nil {
		t.Fatal(err)
	}
	view := state.Profiles[0]
	for i := range view.Variables {
		if view.Variables[i].Key == "API_TOKEN" {
			view.Variables[i].ID = "rotated-id" // no stored original to inherit
		}
	}
	payload, err := app.Dispatch("save-profile", mustJSON(t, map[string]any{"profile": view}))
	if err != nil {
		t.Fatalf("dispatch: %v", err)
	}
	if payload.OK {
		t.Fatal("应当拒绝把掩码写回库")
	}
	stored, err := app.store.Load()
	if err != nil {
		t.Fatal(err)
	}
	for _, variable := range stored.Profiles[0].Variables {
		if variable.Value == maskedValue {
			t.Fatal("掩码被写入配置库")
		}
	}
}

func TestSaveProfileCreatesNewProfile(t *testing.T) {
	app := newTestApp(t)
	created, err := app.Dispatch("save-profile", mustJSON(t, map[string]any{"profile": map[string]any{
		"id": "", "name": "新配置", "note": "",
		"variables": []map[string]any{{"id": "", "key": "NEW_KEY", "value": "v", "enabled": true, "secret": false}},
	}}))
	if err != nil {
		t.Fatalf("dispatch: %v", err)
	}
	if !created.OK {
		t.Fatalf("新建失败：%s", created.Message)
	}
	payload, err := app.store.Load()
	if err != nil {
		t.Fatal(err)
	}
	if len(payload.Profiles) != 2 {
		t.Fatalf("期望 2 个配置，实际 %d", len(payload.Profiles))
	}
	var found bool
	for _, profile := range payload.Profiles {
		if profile.Name == "新配置" {
			found = true
			if profile.ID == "" {
				t.Fatal("新配置没有拿到 ID")
			}
			if len(profile.Variables) != 1 || profile.Variables[0].Key != "NEW_KEY" {
				t.Fatalf("变量未保存：%+v", profile.Variables)
			}
		}
	}
	if !found {
		t.Fatal("新配置未写入配置库")
	}
}

// systemVariables is pure: it turns registry entries into the UI list, so the
// mapping is testable without registry access.
func TestSystemVariablesFromEntries(t *testing.T) {
	payload := &model.VaultPayload{AppliedKeys: []string{"demo_token"}}
	entries := []winsys.EnvEntry{
		{Name: "DEMO_TOKEN", Value: "plain", Expanded: "plain", Type: winsys.RegSZ},
		{Name: "DEMO_REGION", Value: "%USERPROFILE%\\x", Expanded: "C:\\Users\\x", Type: winsys.RegExpandSZ},
		{Name: "EMPTY_BOTH", Value: "", Expanded: ""},
	}
	vars := systemVariables(entries, payload)
	if len(vars) != 2 {
		t.Fatalf("空值应被跳过，得到 %d 条：%+v", len(vars), vars)
	}
	if vars[0].Key != "DEMO_TOKEN" || !vars[0].Applied || vars[0].Kind != "string" {
		t.Fatalf("首条不符合预期：%+v", vars[0])
	}
	if vars[1].Value != "C:\\Users\\x" || vars[1].Kind != "expand" || vars[1].Applied {
		t.Fatalf("展开值或来源标记不符合预期：%+v", vars[1])
	}
}

func TestSystemVariablesMarksSensitive(t *testing.T) {
	vars := systemVariables([]winsys.EnvEntry{{Name: "API_TOKEN", Value: "x", Expanded: "x", Type: winsys.RegSZ}}, &model.VaultPayload{})
	if len(vars) != 1 || !vars[0].Sensitive {
		t.Fatalf("令牌类变量应标记为敏感：%+v", vars)
	}
}

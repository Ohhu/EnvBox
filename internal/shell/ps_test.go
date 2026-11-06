//go:build windows

package shell

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/Ohhu/EnvBox/internal/model"
)

func newTestIntegration(t *testing.T) *Integration {
	t.Helper()
	dir := t.TempDir()
	return &Integration{Dir: dir, ProfilePath: filepath.Join(dir, "profile.ps1")}
}

func TestWriteActivationQuotesValues(t *testing.T) {
	integration := newTestIntegration(t)
	profile := model.EnvProfile{
		ID: "p1", Name: "演示",
		Variables: []model.EnvVariable{
			{ID: "a", Key: "PLAIN", Value: "hello world", IsEnabled: true},
			{ID: "b", Key: "TRICKY", Value: "it's a $env:THING", IsEnabled: true},
			{ID: "c", Key: "OFF", Value: "ignored", IsEnabled: false},
		},
	}
	if err := integration.WriteActivation(profile); err != nil {
		t.Fatalf("write: %v", err)
	}
	raw, err := os.ReadFile(integration.activationPath())
	if err != nil {
		t.Fatal(err)
	}
	content := string(raw)
	if !strings.Contains(content, `$env:PLAIN = 'hello world'`) {
		t.Fatalf("missing plain assignment:\n%s", content)
	}
	// A value with a single quote must be doubled, otherwise the file would not parse.
	if !strings.Contains(content, `$env:TRICKY = 'it''s a $env:THING'`) {
		t.Fatalf("single quotes must be doubled:\n%s", content)
	}
	if strings.Contains(content, "OFF") {
		t.Fatal("disabled variables must not be written")
	}
	if !strings.HasPrefix(content, "# EnvBox 激活快照") {
		t.Fatalf("missing header:\n%s", content)
	}
}

func TestInstallIsIdempotentAndUninstallCleans(t *testing.T) {
	integration := newTestIntegration(t)
	original := "# 我的配置\nSet-Alias ll Get-ChildItem\n"
	if err := os.WriteFile(integration.ProfilePath, []byte(original), 0o600); err != nil {
		t.Fatal(err)
	}

	if err := integration.Install(); err != nil {
		t.Fatalf("install: %v", err)
	}
	if err := integration.Install(); err != nil {
		t.Fatalf("install twice: %v", err)
	}
	raw, _ := os.ReadFile(integration.ProfilePath)
	if strings.Count(string(raw), MarkerStart) != 1 {
		t.Fatalf("managed block duplicated:\n%s", raw)
	}
	if !strings.Contains(string(raw), "Set-Alias ll Get-ChildItem") {
		t.Fatalf("user content must survive:\n%s", raw)
	}
	if !integration.Status().Installed {
		t.Fatal("status should report installed")
	}

	if err := integration.Uninstall(); err != nil {
		t.Fatalf("uninstall: %v", err)
	}
	raw, _ = os.ReadFile(integration.ProfilePath)
	if strings.Contains(string(raw), MarkerStart) || strings.Contains(string(raw), "active.ps1") {
		t.Fatalf("block not removed:\n%s", raw)
	}
	if !strings.Contains(string(raw), "Set-Alias ll Get-ChildItem") {
		t.Fatalf("user content lost:\n%s", raw)
	}
}

func TestMalformedMarkerIsRefused(t *testing.T) {
	integration := newTestIntegration(t)
	broken := MarkerStart + "\n. something\n"
	if err := os.WriteFile(integration.ProfilePath, []byte(broken), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := integration.Install(); err == nil {
		t.Fatal("install must refuse a malformed managed block")
	}
	if err := integration.Uninstall(); err == nil {
		t.Fatal("uninstall must refuse a malformed managed block")
	}
}

func TestStatusJSONFieldNames(t *testing.T) {
	encoded, err := json.Marshal(Status{Installed: true, ProfilePath: "p", ActivationPath: "a", HasActiveSnapshot: true, ShellName: "powershell"})
	if err != nil {
		t.Fatal(err)
	}
	var decoded map[string]any
	if err := json.Unmarshal(encoded, &decoded); err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{"installed", "profilePath", "activationPath", "hasActiveSnapshot", "shellName"} {
		if _, ok := decoded[key]; !ok {
			t.Errorf("缺少字段 %q", key)
		}
	}
	if _, ok := decoded["Installed"]; ok {
		t.Error("字段名泄漏成了 Go 导出名")
	}
}

//go:build windows

package main

import (
	"encoding/json"
	"testing"
)

// The web UI reads lowercase field names; a struct without json tags silently
// breaks a screen (shell status did exactly that), so pin the contract.
func TestStateViewJSONContract(t *testing.T) {
	app := newTestApp(t)
	state, err := app.State()
	if err != nil {
		t.Fatalf("state: %v", err)
	}
	encoded, err := json.Marshal(state)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	var decoded map[string]any
	if err := json.Unmarshal(encoded, &decoded); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	// warning is optional: it only appears when something degraded.
	if value, ok := decoded["warning"]; ok {
		if _, isString := value.(string); !isString {
			t.Errorf("warning 存在但不是字符串：%T", value)
		}
	}
	for _, key := range []string{"version", "channel", "installed", "profiles", "system", "settings", "update", "shell", "mcp", "mcpCommand", "mcpClients", "autostart", "appliedKeys"} {
		if _, ok := decoded[key]; !ok {
			t.Errorf("state 缺少字段 %q", key)
		}
	}
	shellState, ok := decoded["shell"].(map[string]any)
	if !ok {
		t.Fatalf("shell 不是对象：%T", decoded["shell"])
	}
	for _, key := range []string{"installed", "profilePath", "activationPath", "hasActiveSnapshot", "shellName"} {
		if _, ok := shellState[key]; !ok {
			t.Errorf("shell 缺少字段 %q（JSON tag 缺失？）", key)
		}
	}
	autostart, ok := decoded["autostart"].(map[string]any)
	if !ok {
		t.Fatalf("autostart 不是对象：%T", decoded["autostart"])
	}
	if _, ok := autostart["enabled"]; !ok {
		t.Error("autostart 缺少字段 \"enabled\"（设置页会整页报错）")
	}
	if _, ok := decoded["appliedKeys"].([]any); !ok {
		t.Error("appliedKeys 必须是数组")
	}

	updateState, ok := decoded["update"].(map[string]any)
	if !ok {
		t.Fatalf("update 不是对象：%T", decoded["update"])
	}
	for _, key := range []string{"current", "signing", "canInstall", "htmlUrl"} {
		if _, ok := updateState[key]; !ok {
			t.Errorf("update 缺少字段 %q", key)
		}
	}
}

//go:build windows

package mcp

import (
	"encoding/json"
	"strings"
	"testing"
)

const testHelper = "C:\\Program Files\\EnvBox\\bin\\envbox.exe"

func TestClientsMatchThemacOSPresets(t *testing.T) {
	clients := Clients(testHelper)
	if len(clients) != 3 {
		t.Fatalf("expected 3 presets, got %d", len(clients))
	}
	want := []struct{ id, name, label string }{
		{"generic", "通用 JSON", "复制 JSON"},
		{"claudeCode", "Claude Code", "复制命令"},
		{"dsh", "DSH", "复制 YAML"},
	}
	for index, preset := range want {
		got := clients[index]
		if got.ID != preset.id || got.Name != preset.name || got.SnippetLabel != preset.label {
			t.Fatalf("preset %d = %+v, want %v", index, got, preset)
		}
		if !strings.Contains(got.Prompt, got.Snippet) {
			t.Fatalf("%s prompt does not embed the snippet:\n%s", got.ID, got.Prompt)
		}
		if !strings.Contains(got.Prompt, "env_describe") {
			t.Fatalf("%s prompt does not ask for verification:\n%s", got.ID, got.Prompt)
		}
	}
}

func TestGenericSnippetIsValidJSON(t *testing.T) {
	var parsed struct {
		MCPServers map[string]struct {
			Command string   `json:"command"`
			Args    []string `json:"args"`
		} `json:"mcpServers"`
	}
	if err := json.Unmarshal([]byte(jsonSnippet(testHelper)), &parsed); err != nil {
		t.Fatalf("snippet is not valid JSON: %v\n%s", err, jsonSnippet(testHelper))
	}
	server := parsed.MCPServers["envbox"]
	if server.Command != testHelper {
		t.Fatalf("command = %q, want %q", server.Command, testHelper)
	}
	if len(server.Args) != 1 || server.Args[0] != "mcp" {
		t.Fatalf("args = %v, want [mcp]", server.Args)
	}
}

func TestSnippetsQuoteTheBinaryPath(t *testing.T) {
	path := "C:\\Users\\dev\\a b\\envbox.exe"
	command := claudeSnippet(path)
	if !strings.HasPrefix(command, "claude mcp add envbox -- \"") || !strings.HasSuffix(command, "\" mcp") {
		t.Fatalf("claude snippet must quote the path so spaces survive: %s", command)
	}
	if !strings.Contains(dshSnippet(path), "        command: "+path) {
		t.Fatalf("dsh snippet lost the path: %s", dshSnippet(path))
	}
	var parsed map[string]any
	if err := json.Unmarshal([]byte(jsonSnippet(path)), &parsed); err != nil {
		t.Fatalf("quoted path breaks the JSON snippet: %v", err)
	}
}

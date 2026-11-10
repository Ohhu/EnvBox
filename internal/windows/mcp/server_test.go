//go:build windows

package mcp

import (
	"bytes"
	"context"
	"encoding/json"
	"strings"
	"testing"
	"time"

	"github.com/Ohhu/EnvBox/internal/windows/appenv"
)

type stubEnv struct {
	values    map[string]string
	lastCmd   string
	lastOpts  appenv.ExecuteOptions
	exitCode  int
	describeK []string
}

func (s *stubEnv) Describe(keys []string) (*appenv.Description, error) {
	s.describeK = keys
	desc := &appenv.Description{Available: true, Generation: "abc123def456", Profile: "工作"}
	for name, value := range s.values {
		desc.Count++
		desc.Vars = append(desc.Vars, appenv.VarDescription{
			Name: name, Length: len(value), Fingerprint: appenv.Fingerprint(value),
		})
	}
	for _, key := range keys {
		if _, ok := s.values[key]; !ok {
			desc.Missing = append(desc.Missing, key)
		}
	}
	return desc, nil
}

func (s *stubEnv) Execute(_ context.Context, command string, _ time.Duration, options appenv.ExecuteOptions) (*appenv.Result, error) {
	s.lastCmd = command
	s.lastOpts = options
	return &appenv.Result{ExitCode: s.exitCode, Stdout: []byte("ok:" + command)}, nil
}

func (s *stubEnv) Value(key string) (string, bool, error) {
	value, ok := s.values[key]
	return value, ok, nil
}

func run(t *testing.T, server *Server, lines ...string) string {
	t.Helper()
	var out bytes.Buffer
	if err := server.Serve(strings.NewReader(strings.Join(lines, "\n")+"\n"), &out); err != nil {
		t.Fatalf("serve: %v", err)
	}
	return out.String()
}

func decodeAll(t *testing.T, output string) []map[string]any {
	t.Helper()
	var messages []map[string]any
	for _, line := range strings.Split(strings.TrimSpace(output), "\n") {
		if line == "" {
			continue
		}
		var msg map[string]any
		if err := json.Unmarshal([]byte(line), &msg); err != nil {
			t.Fatalf("非 JSON 输出：%q", line)
		}
		messages = append(messages, msg)
	}
	return messages
}

func newServer(env Environment, policy Policy) *Server {
	return &Server{
		Env:     env,
		Policy:  func() Policy { return policy },
		Version: "1.1.0",
	}
}

func TestInitializeAndToolsList(t *testing.T) {
	server := newServer(&stubEnv{values: map[string]string{}}, Policy{Enabled: true})
	output := run(t, server,
		`{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}`,
		`{"jsonrpc":"2.0","id":2,"method":"tools/list"}`,
		`{"jsonrpc":"2.0","method":"notifications/initialized"}`,
	)
	messages := decodeAll(t, output)
	if len(messages) != 2 {
		t.Fatalf("notifications must not be answered, got %d messages: %s", len(messages), output)
	}
	init := messages[0]["result"].(map[string]any)
	if init["protocolVersion"] != "2024-11-05" {
		t.Fatalf("protocol version should echo the client, got %v", init["protocolVersion"])
	}
	info := init["serverInfo"].(map[string]any)
	if info["name"] != "envbox" || info["version"] != "1.1.0" {
		t.Fatalf("unexpected serverInfo %+v", info)
	}
	tools := messages[1]["result"].(map[string]any)["tools"].([]any)
	if len(tools) != 3 {
		t.Fatalf("expected 3 tools, got %d", len(tools))
	}
}

func TestToolsAreDisabledByPolicy(t *testing.T) {
	server := newServer(&stubEnv{values: map[string]string{"A": "1"}}, Policy{Enabled: false})
	output := run(t, server, `{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"env_describe","arguments":{}}}`)
	msg := decodeAll(t, output)[0]
	result := msg["result"].(map[string]any)
	if result["isError"] != true {
		t.Fatalf("expected isError, got %+v", result)
	}
	text := result["content"].([]any)[0].(map[string]any)["text"].(string)
	if !strings.Contains(text, "关闭") {
		t.Fatalf("unexpected text %q", text)
	}
}

func TestDescribeNeverReturnsValues(t *testing.T) {
	env := &stubEnv{values: map[string]string{"API_TOKEN": "s3cret-value"}}
	server := newServer(env, Policy{Enabled: true})
	output := run(t, server, `{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"env_describe","arguments":{"keys":["API_TOKEN"]}}}`)
	text := decodeAll(t, output)[0]["result"].(map[string]any)["content"].([]any)[0].(map[string]any)["text"].(string)
	if strings.Contains(text, "s3cret-value") {
		t.Fatalf("describe leaked the value: %s", text)
	}
	var payload map[string]any
	if err := json.Unmarshal([]byte(text), &payload); err != nil {
		t.Fatalf("payload: %v", err)
	}
	if len(env.describeK) != 1 || env.describeK[0] != "API_TOKEN" {
		t.Fatalf("keys 未透传到 env_describe：%v", env.describeK)
	}
	vars := payload["vars"].([]any)
	first := vars[0].(map[string]any)
	if first["length"].(float64) != float64(len("s3cret-value")) {
		t.Fatalf("unexpected length %v", first["length"])
	}
	if first["fingerprint"] == "" {
		t.Fatal("fingerprint missing")
	}
}

func TestExecPassesCommandAndReportsExit(t *testing.T) {
	env := &stubEnv{values: map[string]string{"A": "1"}, exitCode: 3}
	server := newServer(env, Policy{Enabled: true})
	output := run(t, server, `{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"env_exec","arguments":{"command":"echo hi"}}}`)
	result := decodeAll(t, output)[0]["result"].(map[string]any)
	if result["isError"] != true {
		t.Fatal("non-zero exit must mark isError")
	}
	if env.lastCmd != "echo hi" {
		t.Fatalf("command not forwarded: %q", env.lastCmd)
	}
	text := result["content"].([]any)[0].(map[string]any)["text"].(string)
	if !strings.Contains(text, `"exit":3`) {
		t.Fatalf("unexpected payload %s", text)
	}
}

func TestExecForwardsLoginAndReportsGeneration(t *testing.T) {
	env := &stubEnv{values: map[string]string{"A": "1"}}
	server := newServer(env, Policy{Enabled: true})
	output := run(t, server, `{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"env_exec","arguments":{"command":"echo hi","login":true}}}`)
	if !env.lastOpts.Login {
		t.Fatal("login 未透传到 Execute")
	}
	text := decodeAll(t, output)[0]["result"].(map[string]any)["content"].([]any)[0].(map[string]any)["text"].(string)
	if !strings.Contains(text, `"generation":"abc123def456"`) {
		t.Fatalf("generation 缺失：%s", text)
	}
}

func TestExecRefusesWhenRequiredKeysMissing(t *testing.T) {
	env := &stubEnv{values: map[string]string{"A": "1"}}
	server := newServer(env, Policy{Enabled: true})
	output := run(t, server, `{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"env_exec","arguments":{"command":"echo hi","requiredKeys":["MISSING"]}}}`)
	result := decodeAll(t, output)[0]["result"].(map[string]any)
	if result["isError"] != true {
		t.Fatal("missing required key must fail")
	}
	if env.lastCmd != "" {
		t.Fatalf("command must not run, ran %q", env.lastCmd)
	}
}

func TestRevealRequiresExplicitPolicy(t *testing.T) {
	env := &stubEnv{values: map[string]string{"API_TOKEN": "s3cret-value"}}

	blocked := newServer(env, Policy{Enabled: true, AllowReveal: false})
	out := run(t, blocked, `{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"env_reveal","arguments":{"key":"API_TOKEN"}}}`)
	text := decodeAll(t, out)[0]["result"].(map[string]any)["content"].([]any)[0].(map[string]any)["text"].(string)
	if strings.Contains(text, "s3cret-value") {
		t.Fatal("reveal must be blocked without policy")
	}

	allowed := newServer(env, Policy{Enabled: true, AllowReveal: true})
	out = run(t, allowed, `{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"env_reveal","arguments":{"key":"API_TOKEN"}}}`)
	text = decodeAll(t, out)[0]["result"].(map[string]any)["content"].([]any)[0].(map[string]any)["text"].(string)
	if !strings.Contains(text, "s3cret-value") {
		t.Fatalf("reveal should return the value when enabled, got %s", text)
	}
}

func TestUnknownMethodAndParseError(t *testing.T) {
	server := newServer(&stubEnv{values: map[string]string{}}, Policy{Enabled: true})
	messages := decodeAll(t, run(t, server,
		`{"jsonrpc":"2.0","id":1,"method":"does/not/exist"}`,
		`not json at all`,
	))
	if len(messages) != 2 {
		t.Fatalf("expected two responses, got %d", len(messages))
	}
	if code := messages[0]["error"].(map[string]any)["code"].(float64); code != -32601 {
		t.Fatalf("expected -32601, got %v", code)
	}
	if code := messages[1]["error"].(map[string]any)["code"].(float64); code != -32700 {
		t.Fatalf("expected -32700, got %v", code)
	}
}

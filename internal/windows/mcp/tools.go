//go:build windows

package mcp

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"time"

	"github.com/Ohhu/EnvBox/internal/windows/appenv"
)

// Environment is the subset of appenv.Provider the tools need; tests supply a stub.
type Environment interface {
	Describe(keys []string) (*appenv.Description, error)
	Execute(ctx context.Context, command string, timeout time.Duration) (*appenv.Result, error)
	Value(key string) (string, bool, error)
}

// ToolDescriptors is the payload for tools/list. Descriptions are deliberately
// explicit that env_describe never returns plaintext.
func ToolDescriptors() []map[string]any {
	return []map[string]any{
		{
			"name":        "env_describe",
			"description": "返回变量名、值长度与指纹，不含明文。",
			"inputSchema": map[string]any{
				"type": "object",
				"properties": map[string]any{
					"keys": map[string]any{"type": "array", "items": map[string]any{"type": "string"}},
				},
			},
		},
		{
			"name":        "env_exec",
			"description": "用当前激活配置的环境执行命令，返回退出码、stdout、stderr 与超时/截断标记。",
			"inputSchema": map[string]any{
				"type": "object",
				"properties": map[string]any{
					"command":        map[string]any{"type": "string"},
					"requiredKeys":   map[string]any{"type": "array", "items": map[string]any{"type": "string"}},
					"timeoutSeconds": map[string]any{"type": "number"},
				},
				"required": []string{"command"},
			},
		},
		{
			"name":        "env_reveal",
			"description": "返回指定变量的明文，需先在 EnvBox 中显式启用。",
			"inputSchema": map[string]any{
				"type": "object",
				"properties": map[string]any{
					"key": map[string]any{"type": "string"},
				},
				"required": []string{"key"},
			},
		},
	}
}

type toolResult struct {
	text    string
	isError bool
}

func (s *Server) callTool(req request) *response {
	var params struct {
		Name      string          `json:"name"`
		Arguments json.RawMessage `json:"arguments"`
	}
	if err := json.Unmarshal(req.Params, &params); err != nil || params.Name == "" {
		return s.error(req.ID, -32602, "缺少工具名")
	}

	policy := s.policy()
	if !policy.Enabled {
		return s.toolResponse(req.ID, toolResult{text: `{"error":"` + ErrDisabled.Error() + `"}`, isError: true})
	}
	if s.Env == nil {
		return s.toolResponse(req.ID, toolResult{text: `{"error":"环境不可用"}`, isError: true})
	}

	switch params.Name {
	case "env_describe":
		return s.toolResponse(req.ID, s.describe(params.Arguments))
	case "env_exec":
		return s.toolResponse(req.ID, s.execute(params.Arguments))
	case "env_reveal":
		return s.toolResponse(req.ID, s.reveal(params.Arguments, policy))
	default:
		return s.toolResponse(req.ID, toolResult{text: `{"error":"未知工具"}`, isError: true})
	}
}

func (s *Server) toolResponse(id json.RawMessage, result toolResult) *response {
	return s.result(id, map[string]any{
		"content": []map[string]any{{"type": "text", "text": result.text}},
		"isError": result.isError,
	})
}

func (s *Server) describe(raw json.RawMessage) toolResult {
	var args struct {
		Keys []string `json:"keys"`
	}
	if len(raw) > 0 {
		if err := json.Unmarshal(raw, &args); err != nil {
			return toolResult{text: `{"error":"参数格式错误"}`, isError: true}
		}
	}
	description, err := s.Env.Describe(args.Keys)
	if err != nil {
		return toolResult{text: jsonText(map[string]any{"error": err.Error()}), isError: true}
	}
	return toolResult{text: jsonText(description)}
}

func (s *Server) execute(raw json.RawMessage) toolResult {
	var args struct {
		Command        string   `json:"command"`
		RequiredKeys   []string `json:"requiredKeys"`
		TimeoutSeconds float64  `json:"timeoutSeconds"`
	}
	if len(raw) > 0 {
		if err := json.Unmarshal(raw, &args); err != nil {
			return toolResult{text: `{"error":"参数格式错误"}`, isError: true}
		}
	}
	if strings.TrimSpace(args.Command) == "" {
		return toolResult{text: `{"error":"缺少 command"}`, isError: true}
	}

	// requiredKeys is a guard: refuse to run when the caller expects variables
	// that the active profile does not define, instead of failing mysteriously.
	if len(args.RequiredKeys) > 0 {
		description, err := s.Env.Describe(args.RequiredKeys)
		if err != nil {
			return toolResult{text: jsonText(map[string]any{"error": err.Error()}), isError: true}
		}
		if len(description.Missing) > 0 {
			return toolResult{text: jsonText(map[string]any{
				"error":   "激活配置缺少变量",
				"missing": description.Missing,
			}), isError: true}
		}
	}

	timeout := time.Duration(args.TimeoutSeconds * float64(time.Second))
	result, err := s.Env.Execute(context.Background(), args.Command, timeout)
	if err != nil {
		if errors.Is(err, context.DeadlineExceeded) {
			return toolResult{text: jsonText(map[string]any{"error": "执行超时", "timedOut": true}), isError: true}
		}
		return toolResult{text: jsonText(map[string]any{"error": err.Error()}), isError: true}
	}
	return toolResult{
		text: jsonText(map[string]any{
			"exit":      result.ExitCode,
			"stdout":    string(result.Stdout),
			"stderr":    string(result.Stderr),
			"truncated": result.Truncated,
			"timedOut":  result.TimedOut,
		}),
		isError: result.ExitCode != 0 || result.TimedOut,
	}
}

func (s *Server) reveal(raw json.RawMessage, policy Policy) toolResult {
	if !policy.AllowReveal {
		return toolResult{text: `{"error":"env_reveal 未启用"}`, isError: true}
	}
	var args struct {
		Key string `json:"key"`
	}
	if err := json.Unmarshal(raw, &args); err != nil || strings.TrimSpace(args.Key) == "" {
		return toolResult{text: `{"error":"缺少 key"}`, isError: true}
	}
	value, ok, err := s.Env.Value(args.Key)
	if err != nil {
		return toolResult{text: jsonText(map[string]any{"error": err.Error()}), isError: true}
	}
	if !ok {
		return toolResult{text: jsonText(map[string]any{"key": args.Key, "missing": true})}
	}
	return toolResult{text: jsonText(map[string]any{"key": args.Key, "value": value})}
}

func jsonText(payload any) string {
	encoded, err := json.Marshal(payload)
	if err != nil {
		return `{"error":"序列化失败"}`
	}
	return string(encoded)
}

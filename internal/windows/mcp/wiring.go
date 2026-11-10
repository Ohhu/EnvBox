//go:build windows

package mcp

import (
	"strconv"
	"strings"
)

// Client is one pasteable wiring preset in Settings. The list mirrors the
// macOS app (MCPClient in MCPPolicy.swift) so the copy buttons mean the same
// thing on both platforms: the snippet is what a client config needs, the
// prompt is what an agent needs to add it on its own.
type Client struct {
	ID           string `json:"id"`
	Name         string `json:"name"`
	SnippetLabel string `json:"snippetLabel"`
	Snippet      string `json:"snippet"`
	Prompt       string `json:"prompt"`
}

// Clients builds the presets for binaryPath: the envbox executable without the
// "mcp" argument.
func Clients(binaryPath string) []Client {
	return []Client{
		client("generic", "通用 JSON", "复制 JSON", "你当前的 MCP 配置", binaryPath, jsonSnippet),
		client("claudeCode", "Claude Code", "复制命令", "Claude Code 的 MCP 配置", binaryPath, claudeSnippet),
		client("dsh", "DSH", "复制 YAML", "~/.dsh/cordis.patch.yml", binaryPath, dshSnippet),
	}
}

func client(id, name, label, target, binaryPath string, build func(string) string) Client {
	snippet := build(binaryPath)
	return Client{
		ID:           id,
		Name:         name,
		SnippetLabel: label,
		Snippet:      snippet,
		Prompt:       "将以下 MCP 服务器加入" + target + "，并调用 env_describe 验证。\n\n" + snippet,
	}
}

func jsonSnippet(binaryPath string) string {
	return strings.Join([]string{
		"{",
		"  \"mcpServers\": {",
		"    \"envbox\": {",
		"      \"command\": " + strconv.Quote(binaryPath) + ",",
		"      \"args\": [\"mcp\"]",
		"    }",
		"  }",
		"}",
	}, "\n")
}

func claudeSnippet(binaryPath string) string {
	return "claude mcp add envbox -- " + strconv.Quote(binaryPath) + " mcp"
}

func dshSnippet(binaryPath string) string {
	return strings.Join([]string{
		"- insert:",
		"    - id: envbox-mcp",
		"      name: '@deepseek-ai/dsh-mcp-client'",
		"      config:",
		"        serverName: envbox",
		"        transport: stdio",
		"        command: " + binaryPath,
		"        args: [mcp]",
	}, "\n")
}

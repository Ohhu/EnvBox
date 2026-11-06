//go:build windows

// Package mcp implements the stdio MCP server exposed as `envbox mcp`.
//
// Transport is newline-delimited JSON-RPC 2.0 (the MCP stdio framing), not the
// Content-Length framing used by LSP. Nothing but protocol messages may ever be
// written to stdout: values must not leak into a session log, so diagnostics go
// to stderr and only explicit tool results carry data.
package mcp

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
)

// ProtocolVersion is what we announce when the client does not request one.
const ProtocolVersion = "2025-06-18"

// ServerName is reported in initialize.
const ServerName = "envbox"

type request struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id,omitempty"`
	Method  string          `json:"method"`
	Params  json.RawMessage `json:"params,omitempty"`
}

type response struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id,omitempty"`
	Result  any             `json:"result,omitempty"`
	Error   *rpcError       `json:"error,omitempty"`
}

type rpcError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

// Server serves one stdio session.
type Server struct {
	Env     Environment
	Policy  func() Policy
	Version string
	// Err receives diagnostics; nil silences them.
	Err io.Writer
}

// Serve reads JSON-RPC messages until stdin closes.
func (s *Server) Serve(in io.Reader, out io.Writer) error {
	reader := bufio.NewReaderSize(in, 1<<20)
	writer := bufio.NewWriter(out)
	defer writer.Flush()

	encoder := json.NewEncoder(writer)
	for {
		line, err := reader.ReadBytes('\n')
		if len(line) > 0 {
			if resp := s.handleLine(line); resp != nil {
				if encodeErr := encoder.Encode(resp); encodeErr != nil {
					return encodeErr
				}
				if flushErr := writer.Flush(); flushErr != nil {
					return flushErr
				}
			}
		}
		if err != nil {
			if err == io.EOF {
				return nil
			}
			return err
		}
	}
}

func (s *Server) handleLine(line []byte) *response {
	var req request
	if err := json.Unmarshal(line, &req); err != nil {
		fmt.Fprintf(s.errWriter(), "envbox mcp: 请求解析失败：%v\n", err)
		return &response{JSONRPC: "2.0", Error: &rpcError{Code: -32700, Message: "Parse error"}}
	}
	if req.Method == "" {
		return &response{JSONRPC: "2.0", ID: req.ID, Error: &rpcError{Code: -32600, Message: "Invalid Request"}}
	}
	// Notifications (no id) never get a response.
	isNotification := len(req.ID) == 0 || string(req.ID) == "null"
	if isNotification && (req.Method == "notifications/initialized" || req.Method == "notifications/cancelled") {
		return nil
	}

	switch req.Method {
	case "initialize":
		return s.result(req.ID, map[string]any{
			"protocolVersion": s.negotiate(req.Params),
			"capabilities":    map[string]any{"tools": map[string]any{}},
			"serverInfo":      map[string]any{"name": ServerName, "version": s.version()},
		})
	case "ping":
		return s.result(req.ID, map[string]any{})
	case "tools/list":
		return s.result(req.ID, map[string]any{"tools": ToolDescriptors()})
	case "tools/call":
		return s.callTool(req)
	default:
		if isNotification {
			return nil
		}
		return &response{JSONRPC: "2.0", ID: req.ID, Error: &rpcError{Code: -32601, Message: "Method not found: " + req.Method}}
	}
}

func (s *Server) negotiate(params json.RawMessage) string {
	fallback := ProtocolVersion
	if len(params) == 0 {
		return fallback
	}
	var payload struct {
		ProtocolVersion string `json:"protocolVersion"`
	}
	if err := json.Unmarshal(params, &payload); err != nil || payload.ProtocolVersion == "" {
		return fallback
	}
	// Echo the client version like the macOS build does: the tool surface is
	// small and stable, so there is nothing to gate on protocol revision.
	return payload.ProtocolVersion
}

func (s *Server) version() string {
	if s.Version == "" {
		return "0.0.0"
	}
	return s.Version
}

func (s *Server) result(id json.RawMessage, payload any) *response {
	return &response{JSONRPC: "2.0", ID: id, Result: payload}
}

func (s *Server) error(id json.RawMessage, code int, message string) *response {
	return &response{JSONRPC: "2.0", ID: id, Error: &rpcError{Code: code, Message: message}}
}

func (s *Server) errWriter() io.Writer {
	if s.Err == nil {
		return io.Discard
	}
	return s.Err
}

func (s *Server) policy() Policy {
	if s.Policy == nil {
		return Policy{}
	}
	return s.Policy()
}

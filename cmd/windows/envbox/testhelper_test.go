//go:build windows

package main

import (
	"encoding/json"
	"testing"
)

func mustJSON(t *testing.T, payload any) string {
	t.Helper()
	encoded, err := json.Marshal(payload)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	return string(encoded)
}

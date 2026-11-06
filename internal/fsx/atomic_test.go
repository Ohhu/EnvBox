//go:build windows

package fsx

import (
	"os"
	"path/filepath"
	"testing"
)

func TestWriteFileAtomicReplacesContent(t *testing.T) {
	target := filepath.Join(t.TempDir(), "nested", "file.json")
	if err := WriteFileAtomic(target, []byte("first"), 0o600); err != nil {
		t.Fatalf("write: %v", err)
	}
	if err := WriteFileAtomic(target, []byte("second"), 0o600); err != nil {
		t.Fatalf("overwrite: %v", err)
	}
	data, err := os.ReadFile(target)
	if err != nil {
		t.Fatal(err)
	}
	if string(data) != "second" {
		t.Fatalf("unexpected content %q", data)
	}
	entries, err := os.ReadDir(filepath.Dir(target))
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 1 {
		t.Fatalf("temp files left behind: %d entries", len(entries))
	}
}

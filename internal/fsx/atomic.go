//go:build windows

// Package fsx holds the one atomic-write implementation used by every store.
//
// Four packages used to carry their own temp-file/rename dance, and three of
// them skipped fsync, so a crash could leave a truncated settings file or vault.
package fsx

import (
	"os"
	"path/filepath"
)

// WriteFileAtomic writes data to a sibling temp file, fsyncs it, then renames it
// over target. On Windows the rename is atomic and replaces the destination.
func WriteFileAtomic(target string, data []byte, mode os.FileMode) error {
	dir := filepath.Dir(target)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(dir, ".tmp-*")
	if err != nil {
		return err
	}
	name := tmp.Name()
	cleanup := func() {
		tmp.Close()
		os.Remove(name)
	}
	if _, err := tmp.Write(data); err != nil {
		cleanup()
		return err
	}
	if err := tmp.Sync(); err != nil {
		cleanup()
		return err
	}
	if err := tmp.Close(); err != nil {
		os.Remove(name)
		return err
	}
	if err := os.Chmod(name, mode); err != nil {
		os.Remove(name)
		return err
	}
	if err := os.Rename(name, target); err != nil {
		os.Remove(name)
		return err
	}
	return nil
}

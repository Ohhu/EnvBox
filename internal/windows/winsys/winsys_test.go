//go:build windows

package winsys

import (
	"strings"
	"syscall"
	"testing"
	"unsafe"

	"github.com/Ohhu/EnvBox/internal/core/model"
)

const sandboxEnvKey = `Software\EnvBoxSandbox\Environment`
const sandboxRunKey = `Software\EnvBoxSandbox\Run`

// requireRegistry gives the test a writable sandbox key, skipping when the
// current process cannot write to HKCU (restricted sandbox, locked-down CI).
func requireRegistry(t *testing.T, path string) {
	t.Helper()
	key, err := CreateUserKey(path)
	if err != nil {
		if IsAccessDenied(err) {
			t.Skipf("注册表写入被当前上下文禁止：%v", err)
		}
		t.Fatalf("创建测试键失败：%v", err)
	}
	key.Close()
	t.Cleanup(func() {
		cleanupKey(t, path)
		if parent := parentKeyPath(path); parent != "" {
			cleanupKey(t, parent)
		}
	})
}

// cleanupKey removes every value in a key before deleting it, because
// RegDeleteKeyEx refuses to remove a key that still has subkeys or values.
func cleanupKey(t *testing.T, path string) {
	t.Helper()
	key, err := OpenUserKey(path)
	if err != nil {
		return
	}
	entries, listErr := key.Values()
	key.Close()
	if listErr == nil {
		for _, entry := range entries {
			if writeKey, openErr := OpenUserKey(path); openErr == nil {
				_ = writeKey.DeleteValue(entry.Name)
				writeKey.Close()
			}
		}
	}
	if err := deleteUserKey(path); err != nil && !IsAccessDenied(err) {
		t.Logf("清理测试键 %s 失败：%v", path, err)
	}
}

func parentKeyPath(path string) string {
	idx := strings.LastIndex(path, "\\")
	if idx <= 0 {
		return ""
	}
	return path[:idx]
}

func TestEnvStoreRoundTrip(t *testing.T) {
	requireRegistry(t, sandboxEnvKey)
	store := &EnvStore{KeyPath: sandboxEnvKey}

	profile := singleVar("ENVBOX_TEST_KEY", "hello")
	if _, err := store.Apply(profile, nil); err != nil {
		t.Fatalf("apply: %v", err)
	}
	entry := findEntry(t, store, "envbox_test_key") // case-insensitive lookup
	if entry.Name != "ENVBOX_TEST_KEY" || entry.Value != "hello" {
		t.Fatalf("unexpected entry %+v", entry)
	}

	if _, err := store.Remove([]string{"ENVBOX_TEST_KEY"}); err != nil {
		t.Fatalf("remove: %v", err)
	}
	if _, ok := lookupEntry(store, "ENVBOX_TEST_KEY"); ok {
		t.Fatal("value should be gone")
	}
	if _, err := store.Remove([]string{"ENVBOX_TEST_KEY"}); err != nil {
		t.Fatalf("removing a missing value must not fail: %v", err)
	}
}

func singleVar(key, value string) model.EnvProfile {
	return model.EnvProfile{
		ID: "p1", Name: "测试",
		Variables: []model.EnvVariable{{ID: "a", Key: key, Value: value, IsEnabled: true}},
	}
}

func lookupEntry(store *EnvStore, name string) (EnvEntry, bool) {
	entries, err := store.List()
	if err != nil {
		return EnvEntry{}, false
	}
	for _, entry := range entries {
		if strings.EqualFold(entry.Name, name) {
			return entry, true
		}
	}
	return EnvEntry{}, false
}

func findEntry(t *testing.T, store *EnvStore, name string) EnvEntry {
	t.Helper()
	entry, ok := lookupEntry(store, name)
	if !ok {
		t.Fatalf("找不到变量 %s", name)
	}
	return entry
}
func TestEnvStoreKeepsExpandStringType(t *testing.T) {
	requireRegistry(t, sandboxEnvKey)
	store := &EnvStore{KeyPath: sandboxEnvKey}

	key, err := OpenUserKey(sandboxEnvKey)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	if err := key.SetString("ENVBOX_EXPAND", `%USERPROFILE%\one`, RegExpandSZ); err != nil {
		key.Close()
		t.Fatalf("seed: %v", err)
	}
	key.Close()

	if _, err := store.Apply(singleVar("ENVBOX_EXPAND", `%USERPROFILE%\two`), nil); err != nil {
		t.Fatalf("apply: %v", err)
	}
	entry := findEntry(t, store, "ENVBOX_EXPAND")
	if entry.Type != RegExpandSZ {
		t.Fatalf("REG_EXPAND_SZ must be preserved, got type %d", entry.Type)
	}
	if !strings.Contains(entry.Expanded, `\two`) {
		t.Fatalf("unexpected expansion %q", entry.Expanded)
	}
}
func TestEnvStoreDistinguishesEmptyFromMissing(t *testing.T) {
	requireRegistry(t, sandboxEnvKey)
	store := &EnvStore{KeyPath: sandboxEnvKey}

	if _, err := store.Apply(singleVar("ENVBOX_EMPTY", ""), nil); err != nil {
		t.Fatalf("apply: %v", err)
	}
	entry := findEntry(t, store, "ENVBOX_EMPTY")
	if entry.Value != "" {
		t.Fatalf("expected empty value, got %q", entry.Value)
	}
}
func TestApplyWritesAndPrunes(t *testing.T) {
	requireRegistry(t, sandboxEnvKey)
	store := &EnvStore{KeyPath: sandboxEnvKey}

	if _, err := store.Apply(singleVar("ENVBOX_OLD", "stale"), nil); err != nil {
		t.Fatalf("seed: %v", err)
	}

	profile := model.EnvProfile{
		ID: "p1", Name: "测试",
		Variables: []model.EnvVariable{
			{ID: "a", Key: "ENVBOX_ONE", Value: "1", IsEnabled: true},
			{ID: "b", Key: "ENVBOX_TWO", Value: "2", IsEnabled: true},
			{ID: "c", Key: "ENVBOX_OFF", Value: "3", IsEnabled: false},
		},
	}
	report, err := store.Apply(profile, []string{"ENVBOX_OLD"})
	if err != nil {
		t.Fatalf("apply: %v", err)
	}
	if len(report.Applied) != 2 {
		t.Fatalf("expected 2 applied keys, got %v", report.Applied)
	}
	if len(report.Stale) != 1 || report.Stale[0] != "ENVBOX_OLD" {
		t.Fatalf("expected ENVBOX_OLD to be pruned, got %v", report.Stale)
	}
	if _, ok := lookupEntry(store, "ENVBOX_OFF"); ok {
		t.Fatal("disabled variables must not be written")
	}
}

func TestAutostartRoundTrip(t *testing.T) {
	requireRegistry(t, sandboxRunKey)
	auto := &Autostart{KeyPath: sandboxRunKey}

	exe := `C:\Program Files\EnvBox\EnvBox.exe`
	if err := auto.Enable(exe); err != nil {
		t.Fatalf("enable: %v", err)
	}
	current, ok, err := auto.Current()
	if err != nil || !ok {
		t.Fatalf("current: ok=%v err=%v", ok, err)
	}
	if current != "\""+exe+"\"" {
		t.Fatalf("unexpected command %q", current)
	}
	if err := auto.Disable(); err != nil {
		t.Fatalf("disable: %v", err)
	}
	if err := auto.Disable(); err != nil {
		t.Fatalf("disable must be idempotent: %v", err)
	}
}

func TestDPAPIRoundTrip(t *testing.T) {
	secret := []byte("32-byte-master-key-0000000000000")
	sealed, err := Protect(secret)
	if err != nil {
		t.Fatalf("protect: %v", err)
	}
	if len(sealed) <= len(secret) {
		t.Fatalf("expected sealed to be larger, got %d", len(sealed))
	}
	back, err := Unprotect(sealed)
	if err != nil {
		t.Fatalf("unprotect: %v", err)
	}
	if string(back) != string(secret) {
		t.Fatal("round trip mismatch")
	}
}

func TestSingleInstanceDetectsSecondAcquire(t *testing.T) {
	release, already, err := AcquireSingleInstance()
	if err != nil {
		t.Fatalf("acquire: %v", err)
	}
	defer release()
	if already {
		t.Log("mutex already held by another EnvBox process; second acquire still valid")
	}

	release2, already2, err := AcquireSingleInstance()
	if err != nil {
		t.Fatalf("second acquire: %v", err)
	}
	release2()
	if !already2 {
		t.Fatal("second acquire in the same process must report already running")
	}
}

func TestIsValidKeyMatchesSwiftRules(t *testing.T) {
	valid := []string{"A", "_x", "PATH", "GOOD_KEY_9"}
	for _, key := range valid {
		if !model.IsValidKey(key) {
			t.Fatalf("%q should be valid", key)
		}
	}
	invalid := []string{"", "1A", "A-B", "A B", "A.B"}
	for _, key := range invalid {
		if model.IsValidKey(key) {
			t.Fatalf("%q should be invalid", key)
		}
	}
}

// deleteUserKey removes an empty key; the tests need it for cleanup and the
// production code never deletes whole keys.
func deleteUserKey(path string) error {
	name, err := syscall.UTF16PtrFromString(path)
	if err != nil {
		return err
	}
	lstatus, _, _ := procRegDeleteKeyEx.Call(
		uintptr(syscall.HKEY_CURRENT_USER), uintptr(unsafe.Pointer(name)), 0, 0,
	)
	if lstatus != 0 && syscall.Errno(lstatus) != ErrorFileNotFound {
		return &registryError{op: "删除注册表键", path: path, status: uint32(lstatus), errno: syscall.Errno(lstatus)}
	}
	return nil
}

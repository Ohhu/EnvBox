//go:build windows

package vault

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/Ohhu/EnvBox/internal/core/cryptox"
	"github.com/Ohhu/EnvBox/internal/core/model"
)

func newTestStore(t *testing.T) *Store {
	t.Helper()
	dir := t.TempDir()
	return &Store{Path: filepath.Join(dir, "vault.envbox"), Provider: &MemoryProvider{ID: "key-1"}}
}

func samplePayload() *model.VaultPayload {
	p := model.EmptyVaultPayload(model.Now())
	p.Profiles = []model.EnvProfile{{
		ID: "profile-1", Name: "工作",
		Variables: []model.EnvVariable{{ID: "v1", Key: "API_TOKEN", Value: "s3cret", IsEnabled: true, IsSecret: true}},
	}}
	active := "profile-1"
	p.ActiveProfileID = &active
	return p
}

func TestSaveLoadRoundTrip(t *testing.T) {
	store := newTestStore(t)
	if err := store.Save(samplePayload()); err != nil {
		t.Fatalf("save: %v", err)
	}

	// Only ciphertext on disk: the secret must not appear anywhere in the file.
	raw, err := os.ReadFile(store.Path)
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(raw, []byte("s3cret")) || bytes.Contains(raw, []byte("工作")) {
		t.Fatal("vault file leaks plaintext")
	}

	loaded, err := store.Load()
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	if len(loaded.Profiles) != 1 || loaded.Profiles[0].Variables[0].Value != "s3cret" {
		t.Fatalf("unexpected payload: %+v", loaded)
	}
}

func TestLoadWithoutKeyFails(t *testing.T) {
	store := newTestStore(t)
	if err := store.Save(samplePayload()); err != nil {
		t.Fatal(err)
	}
	store.Provider = &MemoryProvider{} // key lost
	if _, err := store.Load(); err == nil {
		t.Fatal("expected missing key to fail")
	}
}

func TestLoadRejectsKeyIDMismatch(t *testing.T) {
	store := newTestStore(t)
	if err := store.Save(samplePayload()); err != nil {
		t.Fatal(err)
	}
	raw, err := os.ReadFile(store.Path)
	if err != nil {
		t.Fatal(err)
	}
	var envelope model.VaultEnvelope
	if err := json.Unmarshal(raw, &envelope); err != nil {
		t.Fatal(err)
	}
	envelope.KeyID = "another-key"
	mismatched, err := json.Marshal(envelope)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(store.Path, mismatched, 0o600); err != nil {
		t.Fatal(err)
	}
	store.Provider = &MemoryProvider{ID: "another-key", Material: make([]byte, 32)}
	if _, err := store.Load(); err == nil {
		t.Fatal("expected keyID mismatch to fail")
	}
}

func TestLoadMissingFileIsEmptyVault(t *testing.T) {
	store := newTestStore(t)
	payload, err := store.Load()
	if err != nil {
		t.Fatalf("missing file should not error: %v", err)
	}
	if payload.SchemaVersion != model.CurrentSchemaVersion || len(payload.Profiles) != 0 {
		t.Fatalf("unexpected empty payload: %+v", payload)
	}
}

func TestVaultAADIsStable(t *testing.T) {
	if got := string(VaultAAD("abc")); got != "EnvBox.Vault.v1|keyID=abc" {
		t.Fatalf("AAD drift: %s", got)
	}
}

func TestLoadToleratesDuplicateNames(t *testing.T) {
	store := newTestStore(t)
	payload := samplePayload()
	payload.Profiles = []model.EnvProfile{
		{ID: "p1", Name: "同名", Variables: nil},
		{ID: "p2", Name: "同名", Variables: nil},
	}
	active := "p1"
	payload.ActiveProfileID = &active
	// Bypass Save's uniqueness check the way an older build would have.
	key, err := store.Provider.LoadOrCreate()
	if err != nil {
		t.Fatal(err)
	}
	plaintext, err := json.Marshal(payload)
	if err != nil {
		t.Fatal(err)
	}
	sealed, err := cryptox.Seal(key.Material(), plaintext, VaultAAD(key.ID))
	if err != nil {
		t.Fatal(err)
	}
	envelope := model.VaultEnvelope{Format: model.VaultFormat, Version: model.CurrentEnvelopeVersion, KeyID: key.ID, Sealed: sealed}
	encoded, err := json.Marshal(envelope)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(store.Path, encoded, 0o600); err != nil {
		t.Fatal(err)
	}

	loaded, err := store.Load()
	if err != nil {
		t.Fatalf("历史库必须能读出来：%v", err)
	}
	if len(loaded.Profiles) != 2 {
		t.Fatalf("unexpected profiles: %+v", loaded.Profiles)
	}
	if err := store.Save(loaded); err == nil {
		t.Fatal("保存时仍应拒绝重名")
	}
}

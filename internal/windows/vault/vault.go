//go:build windows

// Package vault is the encrypted local configuration store.
//
// Layout mirrors the macOS build: a random 256-bit AES key wrapped by a
// user-scoped protector (Keychain on macOS, DPAPI here) plus an AES-256-GCM
// sealed payload on disk. Only ciphertext touches the filesystem.
package vault

import (
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"

	"github.com/Ohhu/EnvBox/internal/core/cryptox"
	"github.com/Ohhu/EnvBox/internal/core/model"
	"github.com/Ohhu/EnvBox/internal/windows/fsx"
	"github.com/Ohhu/EnvBox/internal/windows/winsys"
)

// vaultAADPrefix must stay byte-identical to CryptoBox.vaultAAD(keyID:).
const vaultAADPrefix = "EnvBox.Vault.v1|keyID="

// VaultAAD builds the additional authenticated data for the vault envelope.
func VaultAAD(keyID string) []byte { return []byte(vaultAADPrefix + keyID) }

// Key is the vault master key.
type Key struct {
	ID       string
	material []byte
}

// newKey copies material so that Key.Zeroize never wipes a provider's buffer.
func newKey(id string, material []byte) *Key {
	owned := append([]byte(nil), material...)
	return &Key{ID: id, material: owned}
}

// Material returns the raw 32 byte key. Callers must not convert it to string.
func (k *Key) Material() []byte { return k.material }

// Zeroize wipes the key material.
func (k *Key) Zeroize() { cryptox.Zeroize(k.material) }

// KeyProvider loads and creates the master key.
type KeyProvider interface {
	// Existing returns the stored key, or false when none exists.
	Existing() (*Key, bool, error)
	// LoadOrCreate returns the stored key, creating one when absent.
	LoadOrCreate() (*Key, error)
}

type storedKey struct {
	ID  string `json:"id"`
	Key []byte `json:"key"`
}

// DPAPIProvider keeps the master key wrapped with DPAPI under %LOCALAPPDATA%.
type DPAPIProvider struct {
	Path string
}

// Existing reads the wrapped key.
func (p *DPAPIProvider) Existing() (*Key, bool, error) {
	raw, err := os.ReadFile(p.Path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil, false, nil
		}
		return nil, false, err
	}
	var stored storedKey
	if err := json.Unmarshal(raw, &stored); err != nil {
		return nil, false, errors.New("vault: 主密钥文件已损坏")
	}
	if stored.ID == "" || len(stored.Key) == 0 {
		return nil, false, errors.New("vault: 主密钥文件不完整")
	}
	material, err := winsys.Unprotect(stored.Key)
	if err != nil {
		return nil, false, err
	}
	if len(material) != cryptox.KeyBytes {
		cryptox.Zeroize(material)
		return nil, false, errors.New("vault: 主密钥长度不合法")
	}
	key := newKey(stored.ID, material)
	cryptox.Zeroize(material)
	return key, true, nil
}

// LoadOrCreate creates a new random key when none is stored yet.
func (p *DPAPIProvider) LoadOrCreate() (*Key, error) {
	if key, ok, err := p.Existing(); err != nil {
		return nil, err
	} else if ok {
		return key, nil
	}

	material, err := cryptox.RandomKey()
	if err != nil {
		return nil, err
	}
	id, err := NewKeyID()
	if err != nil {
		cryptox.Zeroize(material)
		return nil, err
	}
	sealed, err := winsys.Protect(material)
	if err != nil {
		cryptox.Zeroize(material)
		return nil, err
	}
	encoded, err := json.Marshal(storedKey{ID: id, Key: sealed})
	if err != nil {
		cryptox.Zeroize(material)
		return nil, err
	}
	if err := fsx.WriteFileAtomic(p.Path, encoded, 0o600); err != nil {
		cryptox.Zeroize(material)
		return nil, err
	}
	key := newKey(id, material)
	cryptox.Zeroize(material)
	return key, nil
}

// MemoryProvider is used by tests; it keeps the key in memory only.
type MemoryProvider struct {
	ID       string
	Material []byte
}

// Existing returns the in-memory key.
func (p *MemoryProvider) Existing() (*Key, bool, error) {
	if p.Material == nil {
		return nil, false, nil
	}
	return newKey(p.ID, p.Material), true, nil
}

// LoadOrCreate returns the in-memory key, generating one when unset.
func (p *MemoryProvider) LoadOrCreate() (*Key, error) {
	if p.Material != nil {
		return newKey(p.ID, p.Material), nil
	}
	material, err := cryptox.RandomKey()
	if err != nil {
		return nil, err
	}
	if p.ID == "" {
		if p.ID, err = NewKeyID(); err != nil {
			return nil, err
		}
	}
	p.Material = material
	return newKey(p.ID, material), nil
}

// Store is the vault file plus its key provider.
type Store struct {
	Path     string
	Provider KeyProvider
}

// DefaultVaultPath returns <config dir>\vault.envbox, i.e.
// %LOCALAPPDATA%\EnvBox\vault.envbox in production builds.
func DefaultVaultPath() (string, error) {
	dir, err := winsys.ConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "vault.envbox"), nil
}

// DefaultKeyPath returns <config dir>\vault.key.
func DefaultKeyPath() (string, error) {
	dir, err := winsys.ConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "vault.key"), nil
}

// NewStore wires the default paths and the DPAPI key provider.
func NewStore() (*Store, error) {
	vaultPath, err := DefaultVaultPath()
	if err != nil {
		return nil, err
	}
	keyPath, err := DefaultKeyPath()
	if err != nil {
		return nil, err
	}
	return &Store{Path: vaultPath, Provider: &DPAPIProvider{Path: keyPath}}, nil
}

// Load reads and decrypts the vault. A missing file yields an empty payload.
func (s *Store) Load() (*model.VaultPayload, error) {
	raw, err := os.ReadFile(s.Path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return model.EmptyVaultPayload(model.Now()), nil
		}
		return nil, err
	}
	if len(raw) > model.MaxVaultFileBytes {
		return nil, errors.New("vault: 配置库文件超过大小上限")
	}

	var envelope model.VaultEnvelope
	if err := json.Unmarshal(raw, &envelope); err != nil {
		return nil, errors.New("vault: 配置库文件结构无效")
	}
	if envelope.Format != model.VaultFormat {
		return nil, errors.New("vault: 配置库格式标识不匹配")
	}
	if envelope.Version > model.CurrentEnvelopeVersion {
		return nil, fmt.Errorf("vault: 不支持的配置库格式版本 %d", envelope.Version)
	}

	key, ok, err := s.Provider.Existing()
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, errors.New("vault: 缺少主密钥（配置文件存在但密钥被删除）")
	}
	defer key.Zeroize()

	if subtle.ConstantTimeCompare([]byte(key.ID), []byte(envelope.KeyID)) != 1 {
		return nil, errors.New("vault: 主密钥与配置库不匹配")
	}

	plaintext, err := cryptox.Open(key.Material(), envelope.Sealed, VaultAAD(envelope.KeyID))
	if err != nil {
		return nil, err
	}
	var payload model.VaultPayload
	if err := json.Unmarshal(plaintext, &payload); err != nil {
		return nil, errors.New("vault: 配置库明文无法解析")
	}
	if err := model.ValidatePayload(&payload); err != nil {
		return nil, err
	}
	return &payload, nil
}

// Save encrypts and atomically writes the vault.
func (s *Store) Save(payload *model.VaultPayload) error {
	if err := model.ValidatePayload(payload); err != nil {
		return err
	}
	if err := model.ValidateUniqueNames(payload.Profiles); err != nil {
		return err
	}
	payload.UpdatedAt = model.Now()

	key, err := s.Provider.LoadOrCreate()
	if err != nil {
		return err
	}
	defer key.Zeroize()

	plaintext, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	sealed, err := cryptox.Seal(key.Material(), plaintext, VaultAAD(key.ID))
	if err != nil {
		return err
	}
	envelope := model.VaultEnvelope{
		Format:  model.VaultFormat,
		Version: model.CurrentEnvelopeVersion,
		KeyID:   key.ID,
		Sealed:  sealed,
	}
	encoded, err := json.Marshal(envelope)
	if err != nil {
		return err
	}
	if len(encoded) > model.MaxVaultFileBytes {
		return errors.New("vault: 配置库超过大小上限")
	}
	if err := os.MkdirAll(filepath.Dir(s.Path), 0o700); err != nil {
		return err
	}
	return fsx.WriteFileAtomic(s.Path, encoded, 0o600)
}

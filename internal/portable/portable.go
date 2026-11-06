// Package portable implements the password protected .envbox export format.
//
// The wire format is a contract with the macOS build; both sides must produce
// byte-identical AAD input or the file will not decrypt on the other platform.
package portable

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"path/filepath"

	"github.com/Ohhu/EnvBox/internal/cryptox"
	"github.com/Ohhu/EnvBox/internal/fsx"
	"github.com/Ohhu/EnvBox/internal/model"
)

// AAD builds the additional authenticated data exactly as CryptoBox.exportAAD does.
func AAD(format string, version int, kdf string, iterations int, salt []byte) []byte {
	header := fmt.Sprintf(
		"EnvBox.Export.v1|format=%s|version=%d|kdf=%s|iterations=%d|salt=%s",
		format, version, kdf, iterations, base64.StdEncoding.EncodeToString(salt),
	)
	return []byte(header)
}

// Export encrypts profiles into a .envbox document.
func Export(profiles []model.EnvProfile, passphrase string, iterations int, now model.Timestamp) ([]byte, error) {
	if err := validatePassphrase(passphrase); err != nil {
		return nil, err
	}
	if len(profiles) == 0 {
		return nil, errors.New("portable: 没有可导出的配置")
	}
	if iterations == 0 {
		iterations = cryptox.DefaultIterations
	}
	if iterations < cryptox.MinIterations || iterations > cryptox.MaxIterations {
		return nil, errors.New("portable: 迭代次数超出允许范围")
	}

	// Same rules the vault applies; names must be unique in an archive because
	// importing it can only add profiles, never merge them.
	if err := model.ValidateProfiles(profiles, true); err != nil {
		return nil, err
	}

	payload := model.PortableConfiguration{
		SchemaVersion: model.CurrentSchemaVersion,
		Profiles:      profiles,
		ExportedAt:    now,
		Generator:     "EnvBox",
	}
	plaintext, err := json.Marshal(payload)
	if err != nil {
		return nil, err
	}

	salt, err := cryptox.RandomBytes(cryptox.SaltBytes)
	if err != nil {
		return nil, err
	}
	key, err := cryptox.DeriveKey(passphrase, salt, iterations)
	if err != nil {
		return nil, err
	}
	defer cryptox.Zeroize(key)

	aad := AAD(model.ExportFormat, model.CurrentEnvelopeVersion, model.ExportKDF, iterations, salt)
	sealed, err := cryptox.Seal(key, plaintext, aad)
	if err != nil {
		return nil, err
	}

	envelope := model.ExportEnvelope{
		Format:     model.ExportFormat,
		Version:    model.CurrentEnvelopeVersion,
		CreatedAt:  now,
		KDF:        model.ExportKDF,
		Iterations: iterations,
		Salt:       salt,
		Sealed:     sealed,
	}
	encoded, err := json.Marshal(envelope)
	if err != nil {
		return nil, err
	}
	if len(encoded) > model.MaxVaultFileBytes {
		return nil, errors.New("portable: 导出文件超过大小上限")
	}
	return encoded, nil
}

// ExportToFile writes an encrypted .envbox file into dir and returns its path.
func ExportToFile(dir string, profiles []model.EnvProfile, passphrase string, iterations int, now model.Timestamp) (string, error) {
	blob, err := Export(profiles, passphrase, iterations, now)
	if err != nil {
		return "", err
	}
	target := filepath.Join(dir, "envbox-"+now.UTC().Format("20060102-150405")+".envbox")
	if err := fsx.WriteFileAtomic(target, blob, 0o600); err != nil {
		return "", err
	}
	return target, nil
}

// Import decrypts and validates a .envbox document.
func Import(data []byte, passphrase string) (*model.PortableConfiguration, error) {
	if len(data) > model.MaxVaultFileBytes {
		return nil, errors.New("portable: 文件超过大小上限")
	}
	if err := validatePassphrase(passphrase); err != nil {
		return nil, err
	}

	var envelope model.ExportEnvelope
	if err := json.Unmarshal(data, &envelope); err != nil {
		return nil, errors.New("portable: 不是有效的 EnvBox 导出文件")
	}
	if envelope.Format != model.ExportFormat {
		return nil, errors.New("portable: 文件类型不匹配")
	}
	if envelope.Version > model.CurrentEnvelopeVersion {
		return nil, fmt.Errorf("portable: 不支持的归档版本 %d", envelope.Version)
	}
	if envelope.KDF != model.ExportKDF {
		return nil, errors.New("portable: 不支持的密钥派生算法")
	}
	if envelope.Iterations < cryptox.MinIterations || envelope.Iterations > cryptox.MaxIterations {
		return nil, errors.New("portable: 迭代次数超出允许范围")
	}
	if len(envelope.Salt) < 16 || len(envelope.Salt) > 64 {
		return nil, errors.New("portable: 盐值长度不合法")
	}
	if len(envelope.Sealed) == 0 || len(envelope.Sealed) > len(data) {
		return nil, errors.New("portable: 密文长度不合法")
	}

	key, err := cryptox.DeriveKey(passphrase, envelope.Salt, envelope.Iterations)
	if err != nil {
		return nil, err
	}
	defer cryptox.Zeroize(key)

	aad := AAD(envelope.Format, envelope.Version, envelope.KDF, envelope.Iterations, envelope.Salt)
	plaintext, err := cryptox.Open(key, envelope.Sealed, aad)
	if err != nil {
		return nil, err
	}

	var payload model.PortableConfiguration
	if err := json.Unmarshal(plaintext, &payload); err != nil {
		return nil, errors.New("portable: 明文结构无法解析")
	}
	if payload.SchemaVersion > model.CurrentSchemaVersion {
		return nil, fmt.Errorf("portable: 不支持的配置版本 %d", payload.SchemaVersion)
	}
	if err := model.ValidateProfiles(payload.Profiles, true); err != nil {
		return nil, err
	}
	return &payload, nil
}

func validatePassphrase(passphrase string) error {
	n := len([]rune(passphrase))
	if n < 8 {
		return errors.New("portable: 密码至少需要 8 个字符")
	}
	if n > 1024 {
		return errors.New("portable: 密码过长")
	}
	return nil
}

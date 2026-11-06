// Package cryptox holds the primitives shared by the vault and the portable
// export format. Implemented on the standard library only: the whole Windows
// build has zero third-party dependencies, which is what makes it auditable.
package cryptox

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/binary"
	"errors"
	"fmt"
)

// KDF parameters mirrored from the macOS build.
const (
	DefaultIterations = 600_000
	MinIterations     = 100_000
	MaxIterations     = 2_000_000
	SaltBytes         = 16
	KeyBytes          = 32
	NonceBytes        = 12
)

// ErrInvalidArchive is returned for malformed envelope material.
var ErrInvalidArchive = errors.New("cryptox: 归档格式无效")

// ErrBadPassphrase is returned when authentication fails.
var ErrBadPassphrase = errors.New("cryptox: 密码错误或归档已损坏")

// RandomBytes returns n bytes from the OS CSPRNG.
func RandomBytes(n int) ([]byte, error) {
	if n <= 0 || n > 64 {
		return nil, fmt.Errorf("cryptox: 无效长度 %d", n)
	}
	buf := make([]byte, n)
	if _, err := rand.Read(buf); err != nil {
		return nil, err
	}
	return buf, nil
}

// RandomKey returns a fresh 256-bit key.
func RandomKey() ([]byte, error) { return RandomBytes(KeyBytes) }

// DeriveKey runs PBKDF2-HMAC-SHA256 with the given iteration count.
func DeriveKey(passphrase string, salt []byte, iterations int) ([]byte, error) {
	if iterations < MinIterations || iterations > MaxIterations {
		return nil, ErrInvalidArchive
	}
	if len(salt) < 16 || len(salt) > 64 {
		return nil, ErrInvalidArchive
	}
	return PBKDF2SHA256([]byte(passphrase), salt, iterations, KeyBytes), nil
}

// PBKDF2SHA256 implements PBKDF2 with HMAC-SHA256 (RFC 8018).
func PBKDF2SHA256(password, salt []byte, iterations, keyLen int) []byte {
	mac := hmac.New(sha256.New, password)
	hashLen := mac.Size()
	blocks := (keyLen + hashLen - 1) / hashLen
	derived := make([]byte, 0, blocks*hashLen)
	counter := make([]byte, 4)

	for block := 1; block <= blocks; block++ {
		mac.Reset()
		mac.Write(salt)
		binary.BigEndian.PutUint32(counter, uint32(block))
		mac.Write(counter)

		u := mac.Sum(nil)
		t := append([]byte(nil), u...)
		for i := 1; i < iterations; i++ {
			mac.Reset()
			mac.Write(u)
			u = mac.Sum(u[:0])
			for j := range t {
				t[j] ^= u[j]
			}
		}
		derived = append(derived, t...)
	}
	return derived[:keyLen]
}

// Seal encrypts plaintext with AES-256-GCM and returns nonce||ciphertext||tag,
// which is exactly CryptoKit's AES.GCM.SealedBox.combined layout.
func Seal(key, plaintext, aad []byte) ([]byte, error) {
	aead, err := newGCM(key)
	if err != nil {
		return nil, err
	}
	nonce := make([]byte, aead.NonceSize())
	if _, err := rand.Read(nonce); err != nil {
		return nil, err
	}
	return aead.Seal(nonce, nonce, plaintext, aad), nil
}

// Open decrypts a nonce||ciphertext||tag blob.
func Open(key, sealed, aad []byte) ([]byte, error) {
	aead, err := newGCM(key)
	if err != nil {
		return nil, err
	}
	if len(sealed) < aead.NonceSize()+aead.Overhead() {
		return nil, ErrInvalidArchive
	}
	plaintext, err := aead.Open(nil, sealed[:aead.NonceSize()], sealed[aead.NonceSize():], aad)
	if err != nil {
		return nil, ErrBadPassphrase
	}
	return plaintext, nil
}

func newGCM(key []byte) (cipher.AEAD, error) {
	if len(key) != KeyBytes {
		return nil, ErrInvalidArchive
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	return cipher.NewGCM(block)
}

// Zeroize overwrites b so key material does not linger in memory.
// Go cannot guarantee this for strings or for moved heap objects, so callers
// must keep secrets in []byte and never convert them to string.
func Zeroize(b []byte) {
	for i := range b {
		b[i] = 0
	}
}

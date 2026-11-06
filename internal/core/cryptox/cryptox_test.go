package cryptox

import (
	"bytes"
	"encoding/hex"
	"testing"
)

func TestPBKDF2MatchesKnownVectors(t *testing.T) {
	cases := []struct {
		iterations int
		want       string
	}{
		{1, "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b"},
		{2, "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43"},
		{4096, "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a"},
	}
	for _, tc := range cases {
		got := hex.EncodeToString(PBKDF2SHA256([]byte("password"), []byte("salt"), tc.iterations, 32))
		if got != tc.want {
			t.Fatalf("c=%d: got %s want %s", tc.iterations, got, tc.want)
		}
	}
}

func TestSealOpenRoundTripAndTamperDetection(t *testing.T) {
	key, err := RandomKey()
	if err != nil {
		t.Fatal(err)
	}
	aad := []byte("EnvBox.Vault.v1|keyID=test")
	sealed, err := Seal(key, []byte(`{"profiles":[]}`), aad)
	if err != nil {
		t.Fatal(err)
	}
	if len(sealed) != NonceBytes+len(`{"profiles":[]}`)+16 {
		t.Fatalf("unexpected sealed length %d", len(sealed))
	}
	plain, err := Open(key, sealed, aad)
	if err != nil {
		t.Fatal(err)
	}
	if string(plain) != `{"profiles":[]}` {
		t.Fatalf("unexpected plaintext %s", plain)
	}

	if _, err := Open(key, sealed, []byte("other aad")); err == nil {
		t.Fatal("expected AAD mismatch to fail")
	}
	tampered := bytes.Clone(sealed)
	tampered[len(tampered)-1] ^= 0xFF
	if _, err := Open(key, tampered, aad); err == nil {
		t.Fatal("expected tamper detection")
	}
}

func TestDeriveKeyRejectsOutOfRangeIterations(t *testing.T) {
	salt := make([]byte, 16)
	if _, err := DeriveKey("password", salt, 10); err == nil {
		t.Fatal("expected rejection of too few iterations")
	}
	if _, err := DeriveKey("password", salt, 1_000); err == nil {
		t.Fatal("expected rejection below minimum accepted iterations")
	}
}

//go:build windows

package update

import (
	"errors"
	"os"
	"path/filepath"
	"regexp"
	"testing"
)

var hexThumbprint = regexp.MustCompile(`^[0-9A-F]{40}$`)

// explorer.exe carries an embedded Authenticode signature. Files such as
// notepad.exe and cmd.exe are catalog-signed, which is not what we verify: the
// updater only trusts a signature embedded in the installer itself.
const embeddedSignedFixture = `C:\Windows\explorer.exe`

const catalogSignedFixture = `C:\Windows\System32\cmd.exe`

func TestVerifySignatureExtractsSignerThumbprint(t *testing.T) {
	if _, err := os.Stat(embeddedSignedFixture); err != nil {
		t.Skip("缺少可用于验证的系统签名文件")
	}
	thumbprint, err := VerifySignature(embeddedSignedFixture)
	if err != nil {
		t.Fatalf("verify: %v", err)
	}
	if !hexThumbprint.MatchString(thumbprint) {
		t.Fatalf("unexpected thumbprint %q", thumbprint)
	}
}

func TestVerifySignatureRejectsCatalogOnlySignature(t *testing.T) {
	if _, err := os.Stat(catalogSignedFixture); err != nil {
		t.Skip("缺少 catalog 签名的系统文件")
	}
	if _, err := VerifySignature(catalogSignedFixture); err == nil {
		t.Fatal("catalog signatures must not be accepted as embedded ones")
	}
}

func TestVerifySignatureRejectsUnsignedFile(t *testing.T) {
	target := filepath.Join(t.TempDir(), "unsigned.exe")
	if err := os.WriteFile(target, []byte("MZ not really a PE file"), 0o600); err != nil {
		t.Fatal(err)
	}
	_, err := VerifySignature(target)
	if err == nil {
		t.Fatal("unsigned file must be rejected")
	}
	var signatureErr *SignatureError
	if !errors.As(err, &signatureErr) {
		t.Fatalf("expected SignatureError, got %v", err)
	}
}

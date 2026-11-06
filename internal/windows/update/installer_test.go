//go:build windows

package update

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func withUpdateConfigDir(t *testing.T) {
	t.Helper()
	t.Setenv("ENVBOX_CONFIG_DIR", filepath.Join(t.TempDir(), "config"))
}

func TestPendingRoundTrip(t *testing.T) {
	withUpdateConfigDir(t)
	if pending, err := ReadPending(); err != nil || pending != nil {
		t.Fatalf("expected no pending record: %v %+v", err, pending)
	}

	record := Pending{From: "1.1.0", To: "1.2.0", SHA256: "abc", Path: `C:\tmp\setup.exe`, At: "2026-11-02T00:00:00Z"}
	if err := WritePending(record); err != nil {
		t.Fatalf("write: %v", err)
	}
	loaded, err := ReadPending()
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	if loaded == nil || loaded.To != "1.2.0" || loaded.Path != record.Path {
		t.Fatalf("unexpected record %+v", loaded)
	}

	if err := ClearPending(); err != nil {
		t.Fatalf("clear: %v", err)
	}
	if err := ClearPending(); err != nil {
		t.Fatalf("clear must be idempotent: %v", err)
	}
	if pending, _ := ReadPending(); pending != nil {
		t.Fatal("pending record should be gone")
	}
}

func TestSilentArgsAvoidRebootAndUAC(t *testing.T) {
	args := strings.Join(SilentArgs(), " ")
	for _, required := range []string{"/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/CLOSEAPPLICATIONS"} {
		if !strings.Contains(args, required) {
			t.Fatalf("missing %s in %q", required, args)
		}
	}
}

func TestLaunchInstallerRejectsMissingFile(t *testing.T) {
	if err := LaunchInstaller(filepath.Join(t.TempDir(), "missing.exe")); err == nil {
		t.Fatal("missing installer must fail")
	}
}

func TestPruneStagedGuards(t *testing.T) {
	t.Setenv("ENVBOX_CONFIG_DIR", t.TempDir())
	root, err := UpdatesDir()
	if err != nil {
		t.Fatalf("updates dir: %v", err)
	}
	inside := filepath.Join(root, "1.2.3", "setup.exe")
	outside := filepath.Join(filepath.Dir(root), "other", "setup.exe")
	sibling := filepath.Join(filepath.Dir(root), "updates-old", "setup.exe")
	atRoot := filepath.Join(root, "setup.exe")

	cases := []struct {
		name   string
		path   string
		pruned bool
	}{
		{"staged installer", inside, true},
		{"updates root itself", atRoot, false},
		{"prefix sibling", sibling, false},
		{"outside config dir", outside, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			dir := filepath.Dir(tc.path)
			if err := os.MkdirAll(dir, 0o700); err != nil {
				t.Fatal(err)
			}
			if err := PruneStaged(tc.path); err != nil {
				t.Fatalf("prune: %v", err)
			}
			_, statErr := os.Stat(dir)
			if tc.pruned && !os.IsNotExist(statErr) {
				t.Fatalf("expected %s to be removed", dir)
			}
			if !tc.pruned && statErr != nil {
				t.Fatalf("guard removed %s: %v", dir, statErr)
			}
		})
	}
	if err := PruneStaged(""); err != nil {
		t.Fatalf("empty path must be a no-op: %v", err)
	}
}

func TestInstallRejectsTamperedInstaller(t *testing.T) {
	t.Setenv("ENVBOX_CONFIG_DIR", t.TempDir())
	service := &Service{Signer: "00112233445566778899AABBCCDDEEFF00112233"}

	staged := filepath.Join(t.TempDir(), "setup.exe")
	if err := os.WriteFile(staged, []byte("original payload"), 0o600); err != nil {
		t.Fatal(err)
	}
	sum := sha256.Sum256([]byte("original payload"))
	pending := &Pending{To: "1.3.0", SHA256: hex.EncodeToString(sum[:]), Path: staged}
	if err := WritePending(*pending); err != nil {
		t.Fatal(err)
	}

	// Simulate a swapped file: the recorded digest no longer matches.
	if err := os.WriteFile(staged, []byte("tampered payload"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := service.Install(pending); !errors.Is(err, ErrDigest) {
		t.Fatalf("expected ErrDigest, got %v", err)
	}
	if _, statErr := os.Stat(staged); !os.IsNotExist(statErr) {
		t.Fatal("篡改后的安装包应被删除")
	}
	if pending, err := ReadPending(); err != nil || pending != nil {
		t.Fatalf("失败后应清掉待安装记录，got %+v err=%v", pending, err)
	}
}

func TestInstallRejectsMissingDigest(t *testing.T) {
	t.Setenv("ENVBOX_CONFIG_DIR", t.TempDir())
	service := &Service{Signer: "00112233445566778899AABBCCDDEEFF00112233"}

	staged := filepath.Join(t.TempDir(), "setup.exe")
	if err := os.WriteFile(staged, []byte("payload"), 0o600); err != nil {
		t.Fatal(err)
	}
	// A record without a digest must not become a way to skip verification.
	pending := &Pending{To: "1.3.0", Path: staged}
	if err := WritePending(*pending); err != nil {
		t.Fatal(err)
	}
	if err := service.Install(pending); !errors.Is(err, ErrDigest) {
		t.Fatalf("expected ErrDigest for empty digest, got %v", err)
	}
	if _, statErr := os.Stat(staged); !os.IsNotExist(statErr) {
		t.Fatal("缺少摘要时也应删除暂存包")
	}
	if pending, err := ReadPending(); err != nil || pending != nil {
		t.Fatalf("失败后应清掉待安装记录，got %+v err=%v", pending, err)
	}
}

func TestInstallRejectsUnsignedStagedInstaller(t *testing.T) {
	t.Setenv("ENVBOX_CONFIG_DIR", t.TempDir())
	service := &Service{Signer: "00112233445566778899AABBCCDDEEFF00112233"}

	payload := []byte("not signed")
	staged := filepath.Join(t.TempDir(), "setup.exe")
	if err := os.WriteFile(staged, payload, 0o600); err != nil {
		t.Fatal(err)
	}
	sum := sha256.Sum256(payload)
	pending := &Pending{To: "1.3.0", SHA256: hex.EncodeToString(sum[:]), Path: staged}

	// Digest matches but the file has no embedded signature.
	if err := service.Install(pending); !errors.Is(err, ErrSignature) {
		t.Fatalf("expected ErrSignature, got %v", err)
	}
}

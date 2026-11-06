//go:build windows

package update

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"

	"github.com/Ohhu/EnvBox/internal/settings"
)

func newTestService(t *testing.T, handler http.HandlerFunc) (*Service, *httptest.Server) {
	t.Helper()
	t.Setenv("ENVBOX_CONFIG_DIR", filepath.Join(t.TempDir(), "config"))
	server := httptest.NewServer(handler)
	t.Cleanup(server.Close)

	client := NewClient("Ohhu/EnvBox")
	client.BaseURL = server.URL
	client.ExtraHosts = []string{strings.TrimPrefix(server.URL, "http://")}
	return &Service{Client: client, Current: "1.0.0"}, server
}

func releaseHandler(t *testing.T, tag, assetURL string) http.HandlerFunc {
	t.Helper()
	return func(w http.ResponseWriter, r *http.Request) {
		if strings.HasSuffix(r.URL.Path, "/releases/latest") {
			_, _ = w.Write([]byte(`{"tag_name":"` + tag + `","body":"notes","html_url":"https://example.invalid/rel","assets":[
				{"name":"EnvBox-` + strings.TrimPrefix(tag, "v") + `-Windows-amd64-Setup.exe","browser_download_url":"` + assetURL + `","size":10}]}`))
			return
		}
		http.NotFound(w, r)
	}
}

func TestCheckFindsNewerRelease(t *testing.T) {
	service, server := newTestService(t, releaseHandler(t, "v1.3.0", "https://example.invalid/x.exe"))
	available, err := service.Check(context.Background())
	if err != nil {
		t.Fatalf("check: %v", err)
	}
	if available.Version != "1.3.0" || available.Current != "1.0.0" {
		t.Fatalf("unexpected availability %+v", available)
	}
	if !strings.Contains(available.Asset.BrowserDownloadURL, server.URL) && !strings.HasPrefix(available.Asset.BrowserDownloadURL, "https://") {
		t.Fatalf("asset url lost: %s", available.Asset.BrowserDownloadURL)
	}
}

func TestCheckReportsUpToDate(t *testing.T) {
	service, _ := newTestService(t, releaseHandler(t, "v1.0.0", "https://example.invalid/x.exe"))
	if _, err := service.Check(context.Background()); !errors.Is(err, ErrNoUpdate) {
		t.Fatalf("expected ErrNoUpdate, got %v", err)
	}
}

func TestCheckRespectsSkippedVersion(t *testing.T) {
	service, _ := newTestService(t, releaseHandler(t, "v1.3.0", "https://example.invalid/x.exe"))
	current := settings.Load()
	current.Update.SkippedVersion = "1.3.0"
	if err := current.Save(); err != nil {
		t.Fatal(err)
	}
	if _, err := service.Check(context.Background()); !errors.Is(err, ErrSkipped) {
		t.Fatalf("expected ErrSkipped, got %v", err)
	}
}

func TestCheckRespectsDisabledSetting(t *testing.T) {
	service, _ := newTestService(t, releaseHandler(t, "v1.3.0", "https://example.invalid/x.exe"))
	current := settings.Load()
	current.Update.Check = settings.CheckOff
	if err := current.Save(); err != nil {
		t.Fatal(err)
	}
	if _, err := service.Check(context.Background()); !errors.Is(err, settings.ErrDisabled) {
		t.Fatalf("expected ErrDisabled, got %v", err)
	}
}

func TestDownloadFailsClosedWithoutChecksums(t *testing.T) {
	payload := []byte("not a signed installer")
	service, server := newTestService(t, nil)
	// A fingerprint is required to reach the digest stage; unsigned builds stop earlier.
	service.Signer = "00112233445566778899AABBCCDDEEFF00112233"
	service.Client.ExtraHosts = []string{strings.TrimPrefix(server.URL, "http://")}
	server.Config.Handler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case strings.HasSuffix(r.URL.Path, "/releases/latest"):
			_, _ = w.Write([]byte(`{"tag_name":"v1.3.0","assets":[
				{"name":"EnvBox-1.3.0-Windows-amd64-Setup.exe","browser_download_url":"` + server.URL + `/setup.exe","size":22}]}`))
		case strings.HasSuffix(r.URL.Path, "/setup.exe"):
			_, _ = w.Write(payload)
		default:
			http.NotFound(w, r)
		}
	})

	available, err := service.Check(context.Background())
	if err != nil {
		t.Fatalf("check: %v", err)
	}
	if _, err := service.Download(context.Background(), available); !errors.Is(err, ErrDigest) {
		t.Fatalf("expected ErrDigest without checksums, got %v", err)
	}
}

func TestDownloadRejectsUnsignedInstaller(t *testing.T) {
	payload := []byte("not a signed installer")
	sum := sha256.Sum256(payload)
	digest := "sha256:" + hex.EncodeToString(sum[:])

	// The download endpoint must never be reached: the refusal happens first.
	downloads := 0
	service, server := newTestService(t, nil)
	server.Config.Handler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case strings.HasSuffix(r.URL.Path, "/releases/latest"):
			_, _ = w.Write([]byte(`{"tag_name":"v1.3.0","assets":[
				{"name":"EnvBox-1.3.0-Windows-amd64-Setup.exe","browser_download_url":"` + server.URL + `/setup.exe","size":22,"digest":"` + digest + `"}]}`))
		case strings.HasSuffix(r.URL.Path, "/setup.exe"):
			downloads++
			_, _ = w.Write(payload)
		default:
			http.NotFound(w, r)
		}
	})

	available, err := service.Check(context.Background())
	if err != nil {
		t.Fatalf("check: %v", err)
	}
	// An unsigned build has no fingerprint to compare against, so it fails earlier
	// with ErrUnsignedBuild; the UI turns that into "download manually".
	if _, err := service.Download(context.Background(), available); !errors.Is(err, ErrUnsignedBuild) {
		t.Fatalf("expected ErrUnsignedBuild, got %v", err)
	}
	if got := settings.Load().Update.LastResult; got != "unsigned-build" {
		t.Fatalf("last result should record unsigned-build, got %q", got)
	}
	if downloads != 0 {
		t.Fatalf("未签名构建不应发起下载，实际命中 %d 次", downloads)
	}
}

func TestDownloadRejectsWrongSigner(t *testing.T) {
	payload := []byte("not a signed installer")
	sum := sha256.Sum256(payload)
	digest := "sha256:" + hex.EncodeToString(sum[:])

	service, server := newTestService(t, nil)
	service.Signer = "00112233445566778899AABBCCDDEEFF00112233"
	server.Config.Handler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case strings.HasSuffix(r.URL.Path, "/releases/latest"):
			_, _ = w.Write([]byte(`{"tag_name":"v1.3.0","assets":[
				{"name":"EnvBox-1.3.0-Windows-amd64-Setup.exe","browser_download_url":"` + server.URL + `/setup.exe","size":22,"digest":"` + digest + `"}]}`))
		case strings.HasSuffix(r.URL.Path, "/setup.exe"):
			_, _ = w.Write(payload)
		default:
			http.NotFound(w, r)
		}
	})

	available, err := service.Check(context.Background())
	if err != nil {
		t.Fatalf("check: %v", err)
	}
	// With a fingerprint configured the unsigned payload must be rejected as a
	// signature failure, not as "unsigned build".
	if _, err := service.Download(context.Background(), available); !errors.Is(err, ErrSignature) {
		t.Fatalf("expected ErrSignature, got %v", err)
	}
}

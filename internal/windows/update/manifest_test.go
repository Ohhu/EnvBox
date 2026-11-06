package update

import (
	"crypto/sha256"
	"encoding/hex"
	"strings"
	"testing"
)

func releaseJSON(t *testing.T, tag string, assets ...string) []byte {
	t.Helper()
	quoted := make([]string, 0, len(assets))
	for _, a := range assets {
		quoted = append(quoted, `{"name":"`+a+`","browser_download_url":"https://example.invalid/`+a+`","size":10}`)
	}
	body := `{"tag_name":"` + tag + `","draft":false,"prerelease":false,"assets":[` + strings.Join(quoted, ",") + `]}`
	return []byte(body)
}

func TestParseReleaseSelectsInstaller(t *testing.T) {
	release, err := ParseRelease(releaseJSON(t, "v1.2.3",
		"EnvBox-1.2.3-Windows-amd64-Setup.exe", SumsName))
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	version, err := release.Version()
	if err != nil || version != "1.2.3" {
		t.Fatalf("version: %v %q", err, version)
	}
	asset, err := release.Installer()
	if err != nil {
		t.Fatalf("installer: %v", err)
	}
	if asset.Name != "EnvBox-1.2.3-Windows-amd64-Setup.exe" {
		t.Fatalf("unexpected asset %q", asset.Name)
	}
	if _, ok := release.Sums(); !ok {
		t.Fatal("expected sums asset")
	}
}

func TestParseReleaseRejectsUnsuitable(t *testing.T) {
	cases := map[string][]byte{
		"prerelease": []byte(`{"tag_name":"v1.2.3","prerelease":true,"assets":[]}`),
		"draft":      []byte(`{"tag_name":"v1.2.3","draft":true,"assets":[]}`),
		"bad tag":    []byte(`{"tag_name":"v1.2","assets":[]}`),
		"suffixed":   []byte(`{"tag_name":"v1.2.3-rc1","assets":[]}`),
	}
	for name, body := range cases {
		if _, err := ParseRelease(body); err == nil {
			t.Fatalf("%s should be rejected", name)
		}
	}
}

func TestInstallerMissingIsAnError(t *testing.T) {
	release, err := ParseRelease(releaseJSON(t, "v1.2.3", SumsName))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := release.Installer(); err == nil {
		t.Fatal("expected missing installer to fail")
	}
}

func TestCompareVersions(t *testing.T) {
	cases := []struct {
		a, b string
		want int
	}{
		{"1.1.0", "1.2.0", -1},
		{"1.2.0", "1.2.0", 0},
		{"1.10.0", "1.9.9", 1},
		{"v2.0.0", "1.99.99", 1},
	}
	for _, tc := range cases {
		got, err := CompareVersions(tc.a, tc.b)
		if err != nil {
			t.Fatalf("%s vs %s: %v", tc.a, tc.b, err)
		}
		if got != tc.want {
			t.Fatalf("%s vs %s: got %d want %d", tc.a, tc.b, got, tc.want)
		}
	}
	if _, err := CompareVersions("1.0", "1.0.0"); err == nil {
		t.Fatal("expected invalid version to fail")
	}
}

func TestVerifyDigestCrossChecksBothSources(t *testing.T) {
	data := []byte("installer-bytes")
	sum := sha256.Sum256(data)
	hexSum := hex.EncodeToString(sum[:])
	asset := Asset{Name: InstallerName("1.2.3"), Digest: "sha256:" + hexSum}
	sums := []byte(hexSum + "  " + InstallerName("1.2.3") + "\n")

	if err := VerifyDigest(asset, sums, data); err != nil {
		t.Fatalf("expected success: %v", err)
	}
	if err := VerifyDigest(asset, nil, data); err != nil {
		t.Fatalf("digest only should pass: %v", err)
	}
	if err := VerifyDigest(asset, sums, []byte("tampered")); err == nil {
		t.Fatal("expected mismatch")
	}
	if err := VerifyDigest(Asset{Name: InstallerName("1.2.3")}, nil, data); err == nil {
		t.Fatal("no checksum source must fail closed")
	}
	badSums := []byte(strings.Repeat("0", 64) + "  " + InstallerName("1.2.3") + "\n")
	if err := VerifyDigest(Asset{Name: InstallerName("1.2.3")}, badSums, data); err == nil {
		t.Fatal("expected sums mismatch")
	}
}

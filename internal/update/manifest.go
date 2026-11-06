// Package update implements the GitHub Releases based update check.
//
// Only the parts that can be tested offline live here: parsing the release,
// choosing the asset, comparing versions and cross checking digests. The HTTP
// client, signature verification and installer launch are separate.
package update

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
	"strconv"
	"strings"
)

// Asset is one release asset.
type Asset struct {
	Name               string `json:"name"`
	BrowserDownloadURL string `json:"browser_download_url"`
	Size               int64  `json:"size"`
	Digest             string `json:"digest"`
}

// Release is the subset of the GitHub release payload we consume.
type Release struct {
	TagName    string  `json:"tag_name"`
	Name       string  `json:"name"`
	Draft      bool    `json:"draft"`
	Prerelease bool    `json:"prerelease"`
	HTMLURL    string  `json:"html_url"`
	Body       string  `json:"body"`
	Assets     []Asset `json:"assets"`
}

// InstallerNamePattern is the asset the updater will install. The pattern must
// stay stable forever: older installs match on it to find new releases.
const InstallerNamePattern = "EnvBox-%s-Windows-amd64-Setup.exe"

// SumsName is the checksum sidecar asset.
const SumsName = "SHA256SUMS-windows-amd64.txt"

var strictVersion = regexp.MustCompile(`^v?(\d+)\.(\d+)\.(\d+)$`)

// ParseRelease decodes a release payload and rejects anything we must not update to.
func ParseRelease(data []byte) (*Release, error) {
	var release Release
	if err := json.Unmarshal(data, &release); err != nil {
		return nil, errors.New("update: 无法解析发布信息")
	}
	if release.Draft || release.Prerelease {
		return nil, errors.New("update: 该发布不是正式版本")
	}
	if _, err := release.Version(); err != nil {
		return nil, err
	}
	return &release, nil
}

// Version returns the semantic version without the leading "v".
func (r *Release) Version() (string, error) {
	m := strictVersion.FindStringSubmatch(strings.TrimSpace(r.TagName))
	if m == nil {
		return "", fmt.Errorf("update: 标签 %q 不是严格的 vMAJOR.MINOR.PATCH", r.TagName)
	}
	return m[1] + "." + m[2] + "." + m[3], nil
}

// Installer returns the Setup asset for this release.
func (r *Release) Installer() (Asset, error) {
	version, err := r.Version()
	if err != nil {
		return Asset{}, err
	}
	want := InstallerName(version)
	for _, asset := range r.Assets {
		if asset.Name == want {
			if asset.BrowserDownloadURL == "" {
				return Asset{}, errors.New("update: 安装包缺少下载地址")
			}
			return asset, nil
		}
	}
	return Asset{}, fmt.Errorf("update: 该发布缺少 %s（可能还没上传 Windows 安装包）", want)
}

// InstallerName is the asset name the updater installs. Older releases match on
// this pattern, so it must never change.
func InstallerName(version string) string {
	return fmt.Sprintf(InstallerNamePattern, version)
}

// Sums returns the checksum sidecar asset when present.
func (r *Release) Sums() (Asset, bool) {
	for _, asset := range r.Assets {
		if asset.Name == SumsName {
			return asset, true
		}
	}
	return Asset{}, false
}

// CompareVersions compares two "MAJOR.MINOR.PATCH" strings.
// It returns -1 when a < b, 0 when equal and 1 when a > b.
func CompareVersions(a, b string) (int, error) {
	pa, err := parseParts(a)
	if err != nil {
		return 0, err
	}
	pb, err := parseParts(b)
	if err != nil {
		return 0, err
	}
	for i := 0; i < 3; i++ {
		if pa[i] < pb[i] {
			return -1, nil
		}
		if pa[i] > pb[i] {
			return 1, nil
		}
	}
	return 0, nil
}

func parseParts(v string) ([3]int, error) {
	var out [3]int
	m := strictVersion.FindStringSubmatch(strings.TrimSpace(v))
	if m == nil {
		return out, fmt.Errorf("update: 版本号 %q 不合法", v)
	}
	for i := 0; i < 3; i++ {
		n, err := strconv.Atoi(m[i+1])
		if err != nil {
			return out, err
		}
		out[i] = n
	}
	return out, nil
}

// VerifyDigest cross checks the downloaded bytes against the GitHub asset digest
// and, when available, the published SHA256SUMS file. Both sources must agree.
func VerifyDigest(asset Asset, sums []byte, data []byte) error {
	sum := sha256.Sum256(data)
	actual := hex.EncodeToString(sum[:])

	verified := false
	if asset.Digest != "" {
		want, ok := strings.CutPrefix(strings.ToLower(asset.Digest), "sha256:")
		if !ok {
			return fmt.Errorf("update: 不支持的摘要算法 %q", asset.Digest)
		}
		if want != actual {
			return errors.New("update: 安装包摘要与 GitHub 记录不一致")
		}
		verified = true
	}
	if len(sums) > 0 {
		want, ok := lookupSums(sums, asset.Name)
		if !ok {
			return fmt.Errorf("update: 校验文件中缺少 %s", asset.Name)
		}
		if want != actual {
			return errors.New("update: 安装包摘要与 SHA256SUMS 不一致")
		}
		verified = true
	}
	if !verified {
		return errors.New("update: 没有任何可用的校验信息，拒绝安装")
	}
	return nil
}

func lookupSums(sums []byte, name string) (string, bool) {
	// Windows PowerShell 5.1 writes a BOM unless told otherwise; strip it so a
	// checksum file produced there still parses.
	text := strings.TrimPrefix(string(sums), "\ufeff")
	for _, line := range strings.Split(text, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) < 2 {
			continue
		}
		if fields[len(fields)-1] == name {
			return strings.ToLower(fields[0]), true
		}
	}
	return "", false
}

//go:build windows

package update

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/Ohhu/EnvBox/internal/buildinfo"
	"github.com/Ohhu/EnvBox/internal/fsx"
	"github.com/Ohhu/EnvBox/internal/settings"
)

// Sentinel errors the UI maps to messages.
var (
	ErrNoUpdate      = errors.New("update: 已是最新版本")
	ErrSkipped       = errors.New("update: 该版本已被跳过")
	ErrUnsignedBuild = errors.New("update: 当前构建未签名，只能手动下载安装包")
	ErrDigest        = errors.New("update: 安装包完整性校验失败")
	ErrSignature     = errors.New("update: 安装包签名校验未通过")
)

// Available describes a newer release that can be installed.
type Available struct {
	Version string `json:"version"`
	Current string `json:"current"`
	Notes   string `json:"notes,omitempty"`
	HTMLURL string `json:"htmlUrl,omitempty"`
	Asset   Asset  `json:"asset"`
	SumsURL string `json:"sumsUrl,omitempty"`
}

// Service orchestrates check, download and install.
type Service struct {
	Client     *Client
	Current    string
	Signer     string
	CheckClock func() time.Time
}

// NewService builds the production wiring.
func NewService() *Service {
	return &Service{
		Client:     NewClient(buildinfo.UpdateRepo),
		Current:    buildinfo.Version,
		Signer:     buildinfo.SignerThumbprint,
		CheckClock: time.Now,
	}
}

// IsNoOp reports errors that mean "nothing to do", not a failure: up to date,
// skipped version, checking disabled. Both the CLI and the GUI exit successfully
// on these.
func IsNoOp(err error) bool {
	return errors.Is(err, ErrNoUpdate) || errors.Is(err, ErrSkipped) || errors.Is(err, settings.ErrDisabled)
}

// stripPrefix removes a leading "pkg: " marker so wrapped errors do not stack
// prefixes that the UI would then have to peel off twice.
func stripPrefix(err error) string {
	message := err.Error()
	if idx := strings.Index(message, ": "); idx > 0 && !strings.ContainsAny(message[:idx], " ：") {
		return message[idx+2:]
	}
	return message
}

// Check queries GitHub and returns a newer version, or a sentinel error.
func (s *Service) Check(ctx context.Context) (*Available, error) {
	if s.Client == nil {
		return nil, errors.New("update: 客户端未初始化")
	}
	current := settings.Load()
	if current.Update.Check == settings.CheckOff {
		return nil, settings.ErrDisabled
	}

	result, err := s.Client.Latest(ctx, current.Update.ETag)
	if err != nil {
		s.recordCheck("check-failed")
		return nil, err
	}
	if result.ETag != "" && result.ETag != current.Update.ETag {
		_ = settings.Mutate(func(saved *settings.Settings) error {
			saved.Update.ETag = result.ETag
			return nil
		})
	}
	if result.NotModified {
		s.recordCheck("not-modified")
		return nil, ErrNoUpdate
	}

	version, err := result.Release.Version()
	if err != nil {
		s.recordCheck("invalid-tag")
		return nil, err
	}
	comparison, err := CompareVersions(version, s.Current)
	if err != nil {
		return nil, err
	}
	if comparison <= 0 {
		s.recordCheck("up-to-date")
		return nil, ErrNoUpdate
	}
	if strings.TrimSpace(current.Update.SkippedVersion) == version {
		return nil, ErrSkipped
	}

	asset, err := result.Release.Installer()
	if err != nil {
		s.recordCheck("asset-missing")
		return nil, err
	}
	sums, hasSums := result.Release.Sums()
	s.recordCheck("update-available:" + version)
	available := &Available{
		Version: version,
		Current: s.Current,
		Notes:   result.Release.Body,
		HTMLURL: result.Release.HTMLURL,
		Asset:   asset,
	}
	if hasSums {
		available.SumsURL = sums.BrowserDownloadURL
	}
	return available, nil
}

func (s *Service) recordCheck(outcome string) {
	now := time.Now()
	if s.CheckClock != nil {
		now = s.CheckClock()
	}
	// Mutate keeps the background check from clobbering a decision the user just
	// saved in the settings page.
	_ = settings.Mutate(func(current *settings.Settings) error {
		current.Update.MarkChecked(now, outcome)
		return nil
	})
}

// Download fetches the installer, verifies digest and signature, stages it and
// records a pending handoff. Nothing is executed here.
func (s *Service) Download(ctx context.Context, available *Available) (*Pending, error) {
	if available == nil {
		return nil, errors.New("update: 缺少版本信息")
	}
	// Refuse before the transfer: an unsigned build has no fingerprint to compare
	// against, so downloading up to 200 MB first would be wasted work.
	expected := strings.ToUpper(strings.ReplaceAll(s.Signer, " ", ""))
	if expected == "" {
		s.recordCheck("unsigned-build")
		return nil, ErrUnsignedBuild
	}

	data, err := s.Client.Fetch(ctx, available.Asset.BrowserDownloadURL)
	if err != nil {
		return nil, err
	}

	sums, err := s.fetchSums(ctx, available)
	if err != nil {
		return nil, err
	}
	if err := VerifyDigest(available.Asset, sums, data); err != nil {
		s.recordCheck("digest-mismatch")
		return nil, fmt.Errorf("%w：%s", ErrDigest, stripPrefix(err))
	}

	dir, err := UpdatesDir()
	if err != nil {
		return nil, err
	}
	stageDir := filepath.Join(dir, available.Version)
	if err := os.MkdirAll(stageDir, 0o700); err != nil {
		return nil, err
	}
	installerPath := filepath.Join(stageDir, filepath.Base(available.Asset.Name))
	if err := fsx.WriteFileAtomic(installerPath, data, 0o600); err != nil {
		return nil, err
	}

	// The fingerprint is known to be non-empty here; a mismatch means the installer
	// was signed by someone else.
	thumbprint, err := VerifySignature(installerPath)
	if err != nil {
		_ = os.Remove(installerPath)
		s.recordCheck("signature-invalid")
		return nil, fmt.Errorf("%w：%s", ErrSignature, stripPrefix(err))
	}
	if thumbprint != expected {
		_ = os.Remove(installerPath)
		s.recordCheck("signer-mismatch")
		return nil, fmt.Errorf("%w：签名者 %s 与预期 %s 不一致", ErrSignature, thumbprint, expected)
	}

	sum := sha256.Sum256(data)
	pending := &Pending{
		From:   s.Current,
		To:     available.Version,
		SHA256: hex.EncodeToString(sum[:]),
		Path:   installerPath,
		At:     time.Now().UTC().Format(time.RFC3339),
	}
	if err := WritePending(*pending); err != nil {
		_ = os.Remove(installerPath)
		return nil, err
	}
	return pending, nil
}

// fetchSums downloads SHA256SUMS when the release publishes it. A missing file
// is not fatal: the GitHub asset digest alone is still a valid source.
func (s *Service) fetchSums(ctx context.Context, available *Available) ([]byte, error) {
	if s.Client == nil || available.SumsURL == "" {
		return nil, nil
	}
	data, err := s.Client.Fetch(ctx, available.SumsURL)
	if err != nil {
		if strings.Contains(err.Error(), "HTTP 404") {
			return nil, nil
		}
		return nil, err
	}
	return data, nil
}

// Install launches the installer. The caller must exit afterwards so the
// executable can be replaced.
func (s *Service) Install(pending *Pending) error {
	if pending == nil || pending.Path == "" {
		return errors.New("update: 没有待安装的更新包")
	}
	// Re-hash right before launching: the staged file sits on disk between download
	// and install, so a swapped file must not reach the installer.
	// Fail closed and retire the record: a staged file that is gone or unusable
	// would otherwise keep the UI offering an install that cannot succeed.
	discard := func(outcome string) {
		_ = os.Remove(pending.Path)
		_ = ClearPending()
		if outcome != "" {
			s.recordCheck(outcome)
		}
	}

	info, err := os.Stat(pending.Path)
	if err != nil {
		discard("install-missing")
		return fmt.Errorf("update: %s", describeFileError(err))
	}
	if info.Size() > MaxInstallerBytes {
		discard("install-oversize")
		return errors.New("update: 安装包超过大小上限")
	}
	data, err := os.ReadFile(pending.Path)
	if err != nil {
		discard("install-unreadable")
		return fmt.Errorf("update: %s", describeFileError(err))
	}
	sum := sha256.Sum256(data)
	// Fail closed on a missing digest: only a hand-edited record has one, and it
	// must not become a way to skip verification.
	if pending.SHA256 == "" || hex.EncodeToString(sum[:]) != pending.SHA256 {
		discard("digest-mismatch")
		return fmt.Errorf("%w：暂存的安装包已被修改，请重新下载", ErrDigest)
	}

	// The digest lives next to the installer, so it is not an independent trust
	// anchor. Re-check Authenticode and compare against the fingerprint compiled
	// into this binary, which an attacker cannot rewrite without breaking the build.
	expected := strings.ToUpper(strings.ReplaceAll(s.Signer, " ", ""))
	if expected == "" {
		discard("unsigned-build")
		return ErrUnsignedBuild
	}
	thumbprint, err := VerifySignature(pending.Path)
	if err != nil {
		discard("signature-invalid")
		return fmt.Errorf("%w：%s", ErrSignature, stripPrefix(err))
	}
	if thumbprint != expected {
		discard("signer-mismatch")
		return fmt.Errorf("%w：签名者 %s 与预期 %s 不一致", ErrSignature, thumbprint, expected)
	}

	return LaunchInstaller(pending.Path)
}

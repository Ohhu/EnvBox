//go:build windows

package update

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/Ohhu/EnvBox/internal/windows/winsys"
)

// DefaultBaseURL is the GitHub REST endpoint for the latest release.
const DefaultBaseURL = "https://api.github.com"

// MaxInstallerBytes caps the download so a hostile or broken response cannot
// exhaust memory or disk.
const MaxInstallerBytes = 200 << 20

// Client talks to the GitHub Releases API.
type Client struct {
	Repo string
	// BaseURL is overridden by tests to point at a local server.
	BaseURL string
	// ExtraHosts widens the redirect allowlist (tests only).
	ExtraHosts []string
	HTTP       *http.Client
}

// NewClient builds a client with the system proxy and a redirect allowlist.
func NewClient(repo string) *Client {
	client := &Client{Repo: repo, BaseURL: DefaultBaseURL}
	client.HTTP = &http.Client{
		Timeout: 45 * time.Second,
		Transport: &http.Transport{
			Proxy:                 proxyFor,
			TLSHandshakeTimeout:   15 * time.Second,
			ResponseHeaderTimeout: 30 * time.Second,
		},
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			if len(via) >= 5 {
				return errors.New("update: 重定向次数过多")
			}
			if !client.hostAllowed(req.URL.Hostname()) {
				return fmt.Errorf("update: 拒绝重定向到 %s", req.URL.Hostname())
			}
			return nil
		},
	}
	return client
}

// proxyFor skips the proxy for loopback so tests and local mirrors work even on
// machines that only configure a system proxy.
func proxyFor(req *http.Request) (*url.URL, error) {
	switch req.URL.Hostname() {
	case "localhost", "127.0.0.1", "::1":
		return nil, nil
	}
	if resolve := winsys.ProxyFunc(); resolve != nil {
		return resolve(req)
	}
	return nil, nil
}

func (c *Client) hostAllowed(host string) bool {
	host = strings.ToLower(host)
	allowed := []string{"api.github.com", "github.com", "objects.githubusercontent.com", "codeload.github.com", "release-assets.githubusercontent.com"}
	allowed = append(allowed, c.ExtraHosts...)
	for _, candidate := range allowed {
		if host == candidate {
			return true
		}
	}
	return strings.HasSuffix(host, ".githubusercontent.com")
}

// CheckResult is the outcome of one API call.
type CheckResult struct {
	NotModified bool
	ETag        string
	Release     *Release
}

// describeNetworkError turns a transport failure into one Chinese sentence. The
// underlying text is Windows-localised and unhelpful, so it is classified instead
// of echoed.
func describeNetworkError(err error) string {
	message := strings.ToLower(err.Error())
	switch {
	case strings.Contains(message, "refused"):
		return "连接 GitHub 被拒绝，请检查网络或代理"
	case errors.Is(err, context.DeadlineExceeded), strings.Contains(message, "timeout"), strings.Contains(message, "timed out"):
		return "连接 GitHub 超时，请稍后重试"
	case strings.Contains(message, "no such host"), strings.Contains(message, "dns"):
		return "无法解析 api.github.com，请检查 DNS"
	case strings.Contains(message, "certificate"), strings.Contains(message, "tls"):
		return "与 GitHub 的 TLS 握手失败，可能有代理拦截"
	default:
		return "无法连接 GitHub，请检查网络或代理"
	}
}

// Latest fetches the newest release.
func (c *Client) Latest(ctx context.Context, etag string) (*CheckResult, error) {
	if c.HTTP == nil {
		return nil, errors.New("update: 客户端未初始化")
	}
	endpoint := fmt.Sprintf("%s/repos/%s/releases/latest", strings.TrimRight(c.BaseURL, "/"), c.Repo)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("X-GitHub-Api-Version", "2022-11-28")
	req.Header.Set("User-Agent", "EnvBox")
	if etag != "" {
		req.Header.Set("If-None-Match", etag)
	}

	resp, err := c.HTTP.Do(req)
	if err != nil {
		// The raw Go error carries the full API URL and a bare "EOF"; neither helps.
		return nil, fmt.Errorf("update: %s", describeNetworkError(err))
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotModified {
		return &CheckResult{NotModified: true, ETag: etag}, nil
	}
	if resp.StatusCode == http.StatusForbidden || resp.StatusCode == http.StatusTooManyRequests {
		return nil, &RateLimitError{Reset: resp.Header.Get("X-RateLimit-Reset")}
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("update: GitHub 返回 HTTP %d", resp.StatusCode)
	}

	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		// io.ReadAll surfaces "unexpected EOF" and friends; users need an action.
		return nil, errors.New("update: 读取发布信息中断，请重试")
	}
	release, err := ParseRelease(body)
	if err != nil {
		return nil, err
	}
	return &CheckResult{ETag: resp.Header.Get("ETag"), Release: release}, nil
}

// RateLimitError reports that GitHub refused the request for now.
type RateLimitError struct {
	Reset string
}

func (e *RateLimitError) Error() string {
	return "update: GitHub 限制了请求频率，请稍后再试"
}

// Fetch downloads url into memory with a hard cap.
func (c *Client) Fetch(ctx context.Context, rawURL string) ([]byte, error) {
	parsed, err := url.Parse(rawURL)
	if err != nil {
		return nil, err
	}
	if parsed.Scheme != "https" && parsed.Scheme != "http" {
		return nil, errors.New("update: 只允许 http(s) 下载地址")
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, rawURL, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "EnvBox")
	resp, err := c.HTTP.Do(req)
	if err != nil {
		return nil, fmt.Errorf("update: %s", describeNetworkError(err))
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("update: 下载失败 HTTP %d", resp.StatusCode)
	}
	limited := io.LimitReader(resp.Body, MaxInstallerBytes+1)
	data, err := io.ReadAll(limited)
	if err != nil {
		return nil, errors.New("update: 下载中断，请重试")
	}
	if int64(len(data)) > MaxInstallerBytes {
		return nil, errors.New("update: 安装包超过大小上限")
	}
	return data, nil
}

//go:build windows

package update

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func testClient(t *testing.T, handler http.HandlerFunc) (*Client, *httptest.Server) {
	t.Helper()
	server := httptest.NewServer(handler)
	t.Cleanup(server.Close)
	client := NewClient("Ohhu/EnvBox")
	client.BaseURL = server.URL
	client.ExtraHosts = []string{strings.TrimPrefix(server.URL, "http://")}
	return client, server
}

func TestLatestParsesRelease(t *testing.T) {
	client, _ := testClient(t, func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/repos/Ohhu/EnvBox/releases/latest" {
			t.Errorf("unexpected path %s", r.URL.Path)
		}
		if r.Header.Get("Accept") != "application/vnd.github+json" {
			t.Errorf("missing accept header")
		}
		w.Header().Set("ETag", "\"abc\"")
		_, _ = w.Write([]byte(`{"tag_name":"v1.3.0","body":"notes","html_url":"https://github.com/Ohhu/EnvBox/releases/tag/v1.3.0","assets":[
			{"name":"EnvBox-1.3.0-Windows-amd64-Setup.exe","browser_download_url":"https://example.invalid/x.exe","size":10}]}`))
	})
	result, err := client.Latest(context.Background(), "")
	if err != nil {
		t.Fatalf("latest: %v", err)
	}
	if result.NotModified || result.ETag != "\"abc\"" {
		t.Fatalf("unexpected etag handling: %+v", result)
	}
	version, err := result.Release.Version()
	if err != nil || version != "1.3.0" {
		t.Fatalf("version: %v %q", err, version)
	}
}

func TestLatestHandlesNotModified(t *testing.T) {
	client, _ := testClient(t, func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("If-None-Match") != "\"etag\"" {
			t.Errorf("conditional header not sent")
		}
		w.WriteHeader(http.StatusNotModified)
	})
	result, err := client.Latest(context.Background(), "\"etag\"")
	if err != nil {
		t.Fatalf("latest: %v", err)
	}
	if !result.NotModified {
		t.Fatal("expected not modified")
	}
}

func TestLatestReportsRateLimit(t *testing.T) {
	client, _ := testClient(t, func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-RateLimit-Reset", "1700000000")
		w.WriteHeader(http.StatusForbidden)
	})
	_, err := client.Latest(context.Background(), "")
	var rateLimit *RateLimitError
	if !errors.As(err, &rateLimit) {
		t.Fatalf("expected rate limit error, got %v", err)
	}
	if rateLimit.Reset != "1700000000" {
		t.Fatalf("reset header lost: %+v", rateLimit)
	}
}

func TestFetchEnforcesCapAndScheme(t *testing.T) {
	client, _ := testClient(t, func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/missing" {
			http.NotFound(w, r)
			return
		}
		_, _ = w.Write([]byte("installer"))
	})
	data, err := client.Fetch(context.Background(), client.BaseURL+"/x.exe")
	if err != nil || string(data) != "installer" {
		t.Fatalf("fetch: %v %q", err, data)
	}
	if _, err := client.Fetch(context.Background(), "file:///etc/passwd"); err == nil {
		t.Fatal("non http scheme must be rejected")
	}
	if _, err := client.Fetch(context.Background(), client.BaseURL+"/missing"); err == nil {
		t.Fatal("404 must be an error")
	}
}

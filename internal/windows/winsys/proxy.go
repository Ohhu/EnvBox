//go:build windows

package winsys

import (
	"net/http"
	"net/url"
	"os"
	"strings"
)

// ProxyFunc resolves the proxy the updater should use.
//
// Environment variables win because they are explicit. Otherwise the WinINET
// per-user setting is used: most corporate machines configure only the system
// proxy, and without this fallback the update check would fail there with a
// plain connection error.
func ProxyFunc() func(*http.Request) (*url.URL, error) {
	if env := firstEnv("HTTPS_PROXY", "https_proxy", "HTTP_PROXY", "http_proxy"); env != "" {
		if parsed, err := parseProxy(env); err == nil {
			return http.ProxyURL(parsed)
		}
	}
	if parsed := winInetProxy(); parsed != nil {
		return http.ProxyURL(parsed)
	}
	return nil
}

func firstEnv(names ...string) string {
	for _, name := range names {
		if value := strings.TrimSpace(os.Getenv(name)); value != "" {
			return value
		}
	}
	return ""
}

func parseProxy(raw string) (*url.URL, error) {
	if !strings.Contains(raw, "://") {
		raw = "http://" + raw
	}
	return url.Parse(raw)
}

// winInetProxy reads HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings.
// Only the plain "host:port" form is honoured; PAC scripts are not evaluated.
func winInetProxy() *url.URL {
	const keyPath = `Software\Microsoft\Windows\CurrentVersion\Internet Settings`
	key, err := OpenUserKey(keyPath)
	if err != nil {
		return nil
	}
	defer key.Close()

	values, err := key.Values()
	if err != nil {
		return nil
	}
	enabled := false
	server := ""
	for _, value := range values {
		switch strings.ToLower(value.Name) {
		case "proxyenable":
			if len(value.Data) >= 4 {
				enabled = uint32(value.Data[0])|uint32(value.Data[1])<<8|uint32(value.Data[2])<<16|uint32(value.Data[3])<<24 == 1
			}
		case "proxyserver":
			server = decodeUTF16(value.Data)
		}
	}
	if !enabled || server == "" {
		return nil
	}
	if strings.Contains(server, "=") {
		server = pickPerSchemeProxy(server)
	}
	if server == "" {
		return nil
	}
	parsed, err := parseProxy(server)
	if err != nil {
		return nil
	}
	return parsed
}

// pickPerSchemeProxy handles the "http=host:port;https=host:port" form.
func pickPerSchemeProxy(server string) string {
	fallback := ""
	for _, part := range strings.Split(server, ";") {
		scheme, target, ok := strings.Cut(part, "=")
		if !ok || target == "" {
			continue
		}
		if strings.EqualFold(scheme, "https") {
			return target
		}
		if fallback == "" && strings.EqualFold(scheme, "http") {
			fallback = target
		}
	}
	return fallback
}

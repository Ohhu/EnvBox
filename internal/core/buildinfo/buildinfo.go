// Package buildinfo carries values injected at link time.
//
// 版本信息在构建时通过 -ldflags -X 注入，三处必须一致：
// 程序内「关于」、`envbox version`、资源管理器「属性 → 详细信息」。
package buildinfo

var (
	// Channel is "production" for release builds, "dev" for local builds.
	// It must stay a var: -ldflags -X cannot overwrite a const, and the
	// ENVBOX_CONFIG_DIR / ENVBOX_ENV_KEY overrides are gated on it.
	Channel = "dev"
	// Version is the user-facing semantic version, e.g. "1.1.0".
	Version = "0.0.0"
	// BuildNumber is the commit count used as the fourth version component.
	BuildNumber = "0"
	// Commit is the short git commit hash.
	Commit = "unknown"
	// BuildDate is the UTC build timestamp.
	BuildDate = "unknown"
	// UpdateRepo is the GitHub repository used by the updater, "owner/name".
	UpdateRepo = "Ohhu/EnvBox"
	// SignerThumbprint is the SHA-1 thumbprint of the Authenticode certificate.
	// Empty means the build is unsigned and the updater must not auto-install.
	SignerThumbprint = ""
)

// SigningConfigured reports whether downloaded installers can be verified.
func SigningConfigured() bool { return SignerThumbprint != "" }

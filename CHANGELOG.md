# Changelog

All notable changes to EnvBox are documented here.

## [1.1.0] - 2026-10-31

### Added

- MCP server (`EnvBox.app/Contents/Helpers/envbox mcp`) exposing `env_describe`, `env_exec` and `env_reveal`.
- Settings → MCP with a switch, client snippets and one-click copy for JSON or an agent prompt.
- `envbox` helper: `mcp`, `describe`, `exec`, `reveal-policy`, `version`.
- Launch at login, so profiles are applied before manually opened apps start.
- Copy-variable-name action on every variable row and context menu.

### Changed

- `~/.envbox/active.zsh` now starts with a `# Generation:` marker; older files fall back to `# Updated:`.
- Applying a profile shows a hint that already-open command windows keep the old values.

## [1.0.1] - 2026-10-31

### Changed

- Build and release artifacts are now arm64-only.

## [1.0.0] - 2026-10-31

### Added

- Native SwiftUI macOS app for inspecting the live login-shell environment.
- Encrypted, Keychain-backed local vault with up to 100 named profiles.
- Quick switching via the main window and the menu bar.
- Encrypted .envbox import/export protected by PBKDF2-HMAC-SHA256 and AES-256-GCM.
- Optional Zsh integration for applying profiles to new terminal sessions.
- Release-only GitHub Actions workflow producing universal DMG and ZIP artifacts.
- More reliable apply/import/save failure handling and `.zshrc` backups.

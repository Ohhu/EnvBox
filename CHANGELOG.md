# Changelog

All notable changes to EnvBox are documented here.

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

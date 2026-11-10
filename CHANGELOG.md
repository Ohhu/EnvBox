# Changelog

All notable changes to EnvBox are documented here.

## [Unreleased]

## [1.2.0] - 2026-11-06

### Added (Windows)

- Windows x64 port: Go + Wails v3 desktop app, per-user Inno Setup installer, no admin rights required.
- Notification-area icon with the profile list, active-profile checkmark, deactivate and quit; closing the window keeps EnvBox running, and starting it again brings the existing window back.
- CLI and MCP server at `%LOCALAPPDATA%\Programs\EnvBox\bin\envbox.exe`.
- User environment variables written to `HKCU\Environment` with `REG_EXPAND_SZ` preserved, plus `WM_SETTINGCHANGE` notification.
- `.envbox` export from the GUI and `envbox import` (CLI) for macOS-originated archives.
- Opt-out self-update from GitHub Releases with digest cross-check, Authenticode signer pinning and a manual-download fallback for unsigned builds.
- PowerShell integration through a managed `$PROFILE` block plus an `active.ps1` snapshot.
- Settings → MCP now matches macOS: pick a client (通用 JSON / Claude Code / DSH), see the full snippet, then copy the snippet or a ready-made agent prompt.
- Importing a `.envbox` from the GUI: pick the file with the native dialog, type the password, and the profiles are appended. Name and ID clashes are resolved the way macOS does it (suffix, re-key, never overwrite), and the imported profile is selected afterwards.
- Duplicate a profile from its detail page: the copy is named `名称 副本` and numbered when that name is taken.
- Export a single profile from its detail page; 导出全部配置 stays in Settings.
- `env_exec` accepts the macOS `login` argument and reports `generation` in its result. Windows has no login shell, so `login` re-reads the user environment from the registry first — the closest equivalent of a freshly opened terminal. `envbox exec --login` exposes the same switch.

### Changed (Windows)

- Update frequency is configurable (`off`/`daily`/`weekly`, default daily); `envbox update settings --skip-version` skips a release.
- The installer speaks Simplified Chinese on Chinese Windows and English elsewhere, picked from the system display language; `/LANG=zh` or `/LANG=en` forces one.
- Overwriting an install no longer asks the user to close EnvBox: the installer runs `EnvBox.exe --quit` as soon as the wizard opens and waits for the exit right before copying files; the running instance exits on its own, and the uninstaller waits the same way.
- The destination page is always shown, prefilled with the previous folder, instead of the wizard jumping straight to "Ready to Install" on upgrades.

### Fixed (Windows)

- New profiles are written to the vault the moment they are created, so switching views or restarting no longer drops them; creating and renaming both go through a sheet with name and note fields.
- The sidebar footer reports the real state (last write succeeded or failed, how many variables are live on this machine) instead of a fixed "已保存" label.
- Destructive confirmations and the export passphrase use in-app dialogs; the WebView2 chrome dialog titled `wails.localhost 显示` is gone.
- Deleting the active profile first removes its variables from the user environment, so no orphaned keys stay behind.
- Clicking 取消 inside a sheet or dialog closes it again.
- Every variable row has the two copy actions macOS has: 复制变量名 (tag icon) and 复制值, on both the system list and a profile; the system list also gets a per-row 显示值 toggle instead of only the page-wide switch.
- Revealing or copying a secret no longer yields bullets: the list keeps secrets masked on the wire, the eye button asks the host for that one value, and the edit sheet opens with the real text.
- Copying a secret marks the clipboard so Windows history and cloud sync skip it, then clears it after 45 seconds — the same deal macOS already offered.
- The system list conceals a variable whose key any profile marks secret, not only ones whose name looks like a secret: a value saved as `fees` is masked, gets the reveal toggle, and counts as sensitive.
- The sidebar's system row is as wide as a profile row: as a block-level button it shrink-wrapped its content, so its hover highlight stopped 65px short of the selection pill behind it.
- Columns line up again: the action cell is a fixed width (a row with a reveal button used to widen it and shift its value, type and source cells), the row buttons no longer inherit `margin-left: auto` from the standalone utility button (which split the leftover space and left two-button rows 14px off), and the lock icon sits in a reserved slot so a masked key starts at the same x as every other key.
- Upgrading no longer stops at "DeleteFile failed; code 5" on `bin\envbox.exe`: Setup ends any `envbox.exe` still running as an MCP server before it replaces files, waits for the image to be released, and falls back to renaming the file aside if a process still holds it. The uninstaller got the same treatment.

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

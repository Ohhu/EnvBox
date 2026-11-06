# Release checklist

1. Update `VERSION` and `CHANGELOG.md`.
2. Run `swift test` locally.
3. Run `./Scripts/macos/build-app.sh` and smoke-test the app.
4. Commit and push `main`.
5. Create and push a strict stable tag:

   ```bash
   git tag v1.1.1
   git push origin v1.1.1
   ```

6. The release workflow runs the gate, tests, arm64 build, signing/notarization when configured, DMG/ZIP
   packaging and GitHub Release creation. Personal repositories default to ad-hoc packages; set repository
   variable `REQUIRE_SIGNED_RELEASE=true` to make missing Developer ID/notarization credentials fail the build.
   Configure the `release` Environment with required reviewers and protect `v*` tags.
7. Verify the release assets and download the DMG on a clean Mac if possible.

Tags such as `v1.1.1-rc1` intentionally do not build. Only `vMAJOR.MINOR.PATCH` is a formal release.

## Signing credentials (macOS)

| Secret | Purpose |
| --- | --- |
| `MACOS_CERTIFICATE` | Developer ID Application certificate, base64 of the .p12 |
| `MACOS_CERTIFICATE_PASSWORD` | Password of that .p12 |
| `APPLE_ID` | Apple ID used for notarization |
| `APPLE_TEAM_ID` | Team identifier |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password for notarization |
| `KEYCHAIN_PASSWORD` | Temporary keychain password; optional, generated randomly when empty |

`REQUIRE_SIGNED_RELEASE` set to `true` makes the workflow fail when these are missing.

## Windows

The Windows platform is released by `.github/workflows/release-windows.yml` from the same tag. Only x64 is
released and the installer is the only distribution artifact. Both workflows share one GitHub Release:
whichever finishes first creates it, the other reuses it and appends its own section.

Release checklist, signing variables and the updater verification chain are documented in
[WINDOWS-BUILD-RELEASE.md](WINDOWS-BUILD-RELEASE.md) and [WINDOWS-UPDATE.md](WINDOWS-UPDATE.md).

# Release checklist

1. Update `VERSION` and `CHANGELOG.md`.
2. Run `swift test` locally.
3. Run `./Scripts/build-app.sh` and smoke-test the app.
4. Commit and push `main`.
5. Create and push a strict stable tag:

   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```

6. The release workflow runs the gate, tests, arm64 build, signing/notarization when configured, DMG/ZIP
   packaging and GitHub Release creation. Personal repositories default to ad-hoc packages; set repository
   variable `REQUIRE_SIGNED_RELEASE=true` to make missing Developer ID/notarization credentials fail the build.
   Configure the `release` Environment with required reviewers and protect `v*` tags.
7. Verify the release assets and download the DMG on a clean Mac if possible.

Tags such as `v1.0.0-rc1` intentionally do not build. Only `vMAJOR.MINOR.PATCH` is a formal release.

## Signing (optional)

Personal repositories build ad-hoc packages by default. No Apple Developer account is required. Set the
repository variable `REQUIRE_SIGNED_RELEASE=true` to fail the build instead of publishing an unsigned package.

For signed and notarized releases, add these repository secrets:

| Secret | Purpose |
| --- | --- |
| `MACOS_CERTIFICATE` | base64-encoded Developer ID Application `.p12` |
| `MACOS_CERTIFICATE_PASSWORD` | password for the `.p12` |
| `KEYCHAIN_PASSWORD` | temporary CI keychain password (optional; generated if unset) |
| `APPLE_ID` | Apple ID used for notarization |
| `APPLE_TEAM_ID` | Apple Developer Team ID |
| `APPLE_APP_SPECIFIC_PASSWORD` | app-specific password for notarization |

Use the `release` Environment with required reviewers and protect `v*` tags if the repository has multiple
maintainers.

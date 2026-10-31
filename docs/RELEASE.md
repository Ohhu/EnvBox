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

6. The release workflow runs the gate, tests, universal build, mandatory Developer ID signing and notarization,
   DMG/ZIP packaging and GitHub Release creation. Configure the `release` Environment with required reviewers
   and protect `v*` tags. Set repository variable `ALLOW_UNSIGNED_RELEASE=true` only for explicit test builds.
7. Verify the release assets and download the DMG on a clean Mac if possible.

Tags such as `v1.0.0-rc1` intentionally do not build. Only `vMAJOR.MINOR.PATCH` is a formal release.

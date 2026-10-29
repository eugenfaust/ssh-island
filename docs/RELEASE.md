# Distribution

Local builds are ad hoc signed, not Developer ID signed or notarized. `scripts/package.sh` produces a local-test DMG; Gatekeeper may reject this when downloaded on another Mac.

## GitHub Actions and community builds

The [Build and release workflow](../.github/workflows/build.yml) runs on pushes to `main`, pull requests and manual dispatch. It executes `scripts/package.sh` (all core tests and the arm64 release build), verifies the app signature, Info.plist, DMG and SHA-256 checksum, then uploads the DMG/checksum as a 14-day Actions artifact. It does not run interactive Terminal or notch smoke tests on the hosted runner.

The runner label is [`xcode-27`](https://github.blog/changelog/2026-09-10-xcode-27-runner-image-now-runs-on-macos-27/), GitHub's macOS 27 Apple Silicon preview image. This is explicit because the test executable requires macOS 27; `macos-latest` may use an older OS. Preview image availability is controlled by GitHub.

A pushed `v*` tag also publishes a GitHub Release after successful packaging. The tag must exactly match `v` plus `CFBundleShortVersionString` in `Resources/Info.plist`. Update that version and increment `CFBundleVersion` for subsequent releases, commit and push, then tag the intended commit:

```sh
git tag -a v0.1.0 -m 'SSH Island 0.1.0'
git push origin v0.1.0
```

Use a new version for every published release. The workflow uses only the repository-provided `GITHUB_TOKEN`; it needs no personal access token or Apple credentials. Build jobs have read-only repository access, and only the tag's publishing job has `contents: write`. Third-party actions are pinned to commit hashes. Release notes from [RELEASE-NOTES.md](RELEASE-NOTES.md) explain installation, requirements and the ad hoc signature; GitHub appends generated change notes. Keep that file current when changing distribution behavior.

Downloads are **not notarized**. Public distribution through GitHub does not grant Apple trust. The separate Developer ID path below remains available when credentials are configured; Actions currently uses `scripts/package.sh`, not `scripts/release.sh`.

## Developer ID signing and notarization

For public distribution, install full Xcode (including notarytool/stapler), join the Apple Developer Program and install a Developer ID Application certificate. Set a unique bundle identifier in `Resources/Info.plist` and update version/build before release. Do not commit credentials.

Store credentials interactively in the keychain:

```sh
xcrun notarytool store-credentials SSHIsland
```

Then run:

```sh
SIGNING_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)' NOTARY_PROFILE=SSHIsland ./scripts/release.sh
```

The script tests and builds, signs the app with hardened runtime and the Apple Events entitlement, submits a ZIP to Apple, staples the app, packages a DMG, signs/notarizes/staples it and writes a SHA-256 checksum. Notarization transmits the distributable to Apple and requires your credentials; it has not been run for the local build. Review Apple's current distribution requirements before release.

Install the signed result into `/Applications`, validate it with `spctl --assess --type execute --verbose '.../SSH Island.app'`, and complete the README's manual smoke checklist, including Terminal Automation and Login Items. The app intentionally has no App Sandbox entitlement: arbitrary SSH Includes and Terminal automation require access beyond a sandboxed file picker workflow.

The icon is generated from native AppKit drawing code (no third-party assets):

```sh
swift scripts/make-icon.swift "$PWD"
iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
```

Synthetic-host screenshots can be regenerated with `./scripts/smoke.sh`. They contain no user hosts or keys.

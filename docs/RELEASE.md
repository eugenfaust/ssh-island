# Distribution

Local builds are ad hoc signed, not Developer ID signed or notarized. `scripts/package.sh` produces a local-test DMG; Gatekeeper may reject this when downloaded on another Mac.

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

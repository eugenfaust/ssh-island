# SSH Island implementation plan

## Fix duplicate Terminal windows

1. Replace the ordinary Terminal open/reopen before permission checks with AppleScript's documented `launch` command, which skips normal startup window creation. Keep SSH text in the existing structured Apple Event.
2. Extend the real Terminal smoke check: permission requests must create no windows; one connection must add exactly one window. Cover cold launch, running with windows, and running without windows manually.
3. Run automated tests, build the app bundle, and run the controlled localhost smoke check; record any permission or interactive-test limitations.

Completed: 16 automated tests pass; release bundle builds. Real Terminal smoke checks pass both from a stopped Terminal (0 → 1 windows) and with an existing window (1 → 2). Each also verifies three permission requests create no windows and the localhost SSH command executes. Running Terminal with all windows closed and permission denial remain manual checks.

## GitHub automation and first release

1. Add CI for pushes/PRs using the macOS 27 ARM64 `xcode-27` runner; test, build, verify and upload DMG/checksum artifacts.
2. Publish tagged versions through GitHub Actions with explicit ad hoc signing limitations and version/tag validation.
3. Validate packaging locally and the workflow on GitHub, then publish `v0.1.0` and verify downloadable assets.

Completed: hosted CI and the tagged release workflow passed; `v0.1.0` is public with a DMG and SHA-256 checksum. Downloaded assets were verified without authentication. Future releases use Node.js 24 artifact actions. Developer ID signing/notarization still requires Apple credentials.

1. M1: Swift 6 package and reproducible arm64 macOS 27 app bundle; alias parser, safe Terminal launch, accessory lifecycle, notch overlay and menu fallback, settings/quit. Build and test.
2. M2: recursive Includes, globbing, diagnostics, replacement-safe watching, favorites/recents/search, display and wake handling. Extend tests and rebuild.
3. M3: keyboard navigation, reduced motion, configurable Carbon hotkey, login item, terminal adapter, icon, packaging/release documentation and smoke checks.

Environment: macOS 27.0.1, Apple Silicon, Swift 6.3.2 / Command Line Tools SDK. Full Xcode is absent. Use Swift Package Manager plus an app-bundle script (no dependencies); validate with the available Apple SDK/compiler. Signing/notarization requires distribution credentials.

## Implemented

- M1: built and launched the native accessory app bundle. Notch-gap trigger plus full-height overlay with controls below the safe inset; Terminal structured Apple Event adapter; menu-bar fallback, settings, quit and README.
- M2: recursive parser with injected reads/globs, bounded traversal and diagnostics; replacement-safe metadata watching and debounce; persistence, favorites, recent hosts, search, screen/wake/Space updates and geometry tests.
- M3: keyboard event checks, reduced motion, accessibility labels, configurable hotkey with conflict feedback, SMAppService login option, native icon, MIT license, synthetic screenshots, DMG packaging and credential-gated release script.

Validation: 16 automatic tests and 32 UI integration checks pass on the detected built-in notch. See docs/VALIDATION.md. Real Terminal execution now passes via a LaunchServices-launched controlled localhost test, after fixing TCC attribution, explicit consent requests and local signing entitlements. WindowServer checks verify the overlay is above the status bar and the camera trigger is not clamped below it. Physical display/login scenarios remain manual release checks. The app and local-test DMG are ad hoc signed; no notarization is claimed.

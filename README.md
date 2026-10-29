# SSH Island

A native Swift 6 macOS utility that extends the camera notch into a small SSH launcher. Hover for favorites/recent aliases, click the expand control or heading for searchable hosts, and select an alias to open a new Terminal.app session running `/usr/bin/ssh '<alias>'`.

Apple Silicon, macOS 27+. No dependencies, server, telemetry, host probing or credential storage. This is an AppKit overlay, not integration with a system Dynamic Island.

Download a DMG from [GitHub Releases](https://github.com/eugenfaust/ssh-island/releases/latest). Community packages are **ad hoc signed, not notarized**, so macOS may block them; see the release's installation notes. [GitHub Actions](https://github.com/eugenfaust/ssh-island/actions) tests and packages pushes/PRs and publishes version tags with a DMG and SHA-256 checksum.

## Build and run

```sh
./scripts/build.sh
open 'build/SSH Island.app'
```

The script builds arm64 with Swift Package Manager, creates a real `LSUIElement` app bundle and applies an **ad hoc** local signature with hardened runtime and the Apple Events entitlement. Requires Apple Command Line Tools with Swift 6 and a macOS SDK (`xcode-select --install`), or full Xcode. Xcode is not needed for this package-based build. The target machine used for validation has macOS 27.0.1, Swift 6.3.2 and CLT SDK 26.5; the binary explicitly targets macOS 27.0. The implementation uses APIs already available in that SDK.

Install by copying `build/SSH Island.app` into `/Applications`. Keep the installed path stable when enabling login launch or granting Automation permission. Rebuilding/replacing an ad hoc app can require granting permission again.

## Use

- Hover over the slim black strip immediately below the built-in camera notch. The preview prioritizes favorites, then recent aliases, then configuration order. Stars toggle favorites. The **All N hosts** button opens the complete list; the preview intentionally shows only four entries.
- Click the heading/expand control for the full list. Search, use ↑/↓ to select, Return to connect and Escape or Close to dismiss. The expanded viewport keeps its height during filtering, including no-result searches; clearing search restores the complete scrollable list. Tab also traverses the buttons. Leaving the preview dismisses it after a short delay; expanded content remains until dismissed.
- Click the menu-bar terminal icon to toggle the launcher. Right-click for Refresh, Settings and Quit. The island's ellipsis menu provides these actions too.
- In Settings → Island, turn off **Show icon in menu bar** to hide the terminal icon. The choice applies immediately and is saved. Settings/Quit remain in the island’s ellipsis menu; reopening the running `.app` through Finder or `open` also shows Settings. If the overlay is disabled or no notched display is available, the icon automatically reappears until the overlay is available again.
- Settings includes animation, overlay, global shortcut and Launch at Login. Default shortcut: **Control–Option–Command–Space**. Change modifiers/key or disable it if another app owns it. Registration failure appears in Settings and the status icon tooltip.
- If no reliable built-in notch geometry exists, the icon opens a popover with an explanation. Disabling the overlay also uses the popover.
- Terminal is the supported terminal adapter. In Settings → Terminal, click **Request Terminal access** to trigger macOS consent without running SSH; connecting also requests consent if needed. Only after a request can macOS list the app under Privacy & Security → Automation. If listed, enable SSH Island → Terminal there. If the entry is absent, quit and reopen the `.app` using Finder or `open`; do not launch `Contents/MacOS/SSHIsland` directly from an IDE, which can attribute the permission request to the IDE. No Accessibility or Full Disk Access is requested.

## Configuration and security

SSH Island indexes `~/.ssh/config` and recursive `Include` files. It shows explicit `Host` aliases, preserving order and deduplicating identical names; wildcard/negated entries (`*`, `?`, `!`) are excluded. Multiple aliases, whitespace, `=`, comments and quoted paths are supported. Nested relative Includes resolve against **`~/.ssh`**, not the including file's directory, following [OpenSSH's documented semantics](https://man.openbsd.org/ssh_config#Include). Globs expand in lexical order, with tilde expansion, cycle detection, a 32-level/1024-file traversal limit, and a 2 MiB per-file limit.

This is an alias index, not OpenSSH's evaluator. All literal Host declarations and Includes are indexed regardless of surrounding Host/Match conditions. `Match exec` is never executed. Connection-specific `%` tokens and `${ENV}` expansion in Include paths are skipped with a diagnostic; system-wide `/etc/ssh/ssh_config` is not indexed. Invalid quoting/unreadable included files produce warnings. A failed root-config read is retried once after 250 ms; persistent failures show a distinct configuration error with its source path and a Retry action, rather than “No SSH aliases yet.” Missing root config and unmatched globs are valid empty states. OpenSSH ultimately decides whether unusual literal aliases (e.g. whitespace) are valid destinations.

Connections use the **alias**, retaining OpenSSH configuration for User, Port, IdentityFile, ProxyJump and Match. Alias text is quoted as one POSIX shell argument and delivered as a typed Apple Event text parameter. Leading hyphens and control characters are rejected with feedback. The app never invokes `sh -c` to connect, executes config content or reads identities/passwords. The adapter sends Terminal's public `do script` (`core/dosc`) Apple Event directly using `NSAppleEventDescriptor`, verified against the installed Terminal.sdef. It creates no AppleScript source. The typed parameter preserves the command text; shell quoting remains necessary because Terminal executes it in the user's shell (POSIX-compatible quoting is expected, as in macOS's default zsh). No shell history command is issued; Terminal's shell may retain commands according to the user's history settings.

Favorites (aliases only), the last 12 recent aliases, terminal choice and UI/shortcut preferences are stored in local UserDefaults (`org.sshisland.app`). Recents are recorded when Terminal accepts the launch, not when SSH authenticates; the app does not inspect terminal sessions. Clear recents in Settings. The application does not read private key contents, perform network discovery or log hostnames/credentials.

Config watching polls **metadata only every 1.5 seconds**, followed by a 350 ms debounce, then reparses off the main thread. It tracks files, resolved symlink targets, include directories/glob prefixes and missing-path ancestors. Watching paths rather than persistent file descriptors survives atomic replacement and deletion/recreation. Refresh is always available. A change-and-revert entirely between polls can be missed; use Refresh in that case.

## Display behavior and limitations

The panel uses public [NSScreen safe-area](https://developer.apple.com/documentation/appkit/nsscreen/safeareainsets) and [auxiliary-area geometry](https://developer.apple.com/documentation/appkit/nsscreen/auxiliarytopleftarea), together with `CGDisplayIsBuiltin`. It uses global screen coordinates and never selects `NSScreen.main` as a substitute for a built-in notched screen. A narrow tracking panel occupies only the camera gap itself, so hovering the cutout also reveals the preview. The black outline starts at the display top in every state and grows across the menu bar to the current island width. This deliberately covers the central menu-bar area while preview/expanded content is visible, giving the camera and launcher one continuous silhouette. All controls remain **below** the camera inset. Escape, Close or an outside click restores the collapsed width; exact physical cutout dimensions are not exposed by a public API.

Screen-change, active-Space and wake notifications recalculate placement. Both overlay windows use one level above `NSWindow.Level.statusBar` and below pop-up menus. The borderless panel overrides AppKit’s frame constraint because the island deliberately reaches above `visibleFrame` and temporarily covers menu controls within its width. The panel requests all-Spaces/full-screen-auxiliary behavior. macOS controls final window ordering: exclusive full-screen apps, screen locking, Stage Manager and compatibility/scaled display modes can restrict visibility or geometry. The menu-bar fallback remains the supported alternative. Physical external monitor hot-plug, sleep/wake and full-screen Spaces need the manual checks below on each target setup.

## Tests and packaging

```sh
./scripts/test.sh       # parser, injection/escaping, geometry, persistence and real file-watcher tests
./scripts/smoke.sh      # launch accessory app; injected terminal, synthetic hosts, own-view PNG captures
./scripts/terminal-smoke.sh # real Automation attempt, localhost:1 only; may prompt/deny
./scripts/package.sh    # tests + release app + build/SSH-Island.dmg
```

The installed Command Line Tools omit both XCTest and Swift Testing. Tests therefore use a small dependency-free Swift assertion runner, compiled and executed by SwiftPM; **use `scripts/test.sh`, not `swift test`**. Shell quoting tests round-trip hostile-looking aliases through `printf`, round-trip the command through a typed Apple Event parameter without sending it, and reject unsafe aliases. Integration tests exercise atomic replacement, new glob matches and deletion. UI checks write `build/smoke/smoke.txt` and PNGs; these are actual app-view captures with synthetic aliases, not captures of the user's configuration. UI checks do not authenticate or send SSH traffic.

Manual release smoke checklist:

1. Hover → preview → move into rows → expand → type search → arrow keys/Return. Confirm preview does not disappear while entering it. Test Escape, outside click, Settings and Quit.
2. Select a controlled local alias with Terminal Automation permission allowed, then denied; check a new window executes SSH, prompts remain interactive and denial explains recovery. The localhost execution path is covered separately by `scripts/terminal-smoke.sh`; authenticating to your own controlled host remains a manual check.
3. Connect/disconnect an external monitor, rearrange screens, change resolution, sleep/wake, use full-screen Spaces and auto-hiding menu bar. Confirm the island stays on the built-in notch or falls back visibly.
4. Check VoiceOver, keyboard-only operation, Reduce Motion, shortcut conflict and Launch at Login from `/Applications`. Login items use [SMAppService.mainApp](https://developer.apple.com/documentation/servicemanagement/smappservice) and may require approval in System Settings.

See [validation notes](docs/VALIDATION.md) for the checks actually executed and [release instructions](docs/RELEASE.md) for Developer ID signing/notarization. MIT licensed.

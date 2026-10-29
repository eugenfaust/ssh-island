Native macOS SSH launcher attached to the MacBook camera notch. Hover for favorite/recent hosts, expand to search all SSH aliases, and connect in Terminal.app.

## Download and install

- Requires **Apple Silicon and macOS 27 or later**.
- Download `SSH-Island.dmg`, open it and drag **SSH Island.app** to **Applications**.
- `SSH-Island.dmg.sha256` provides the download's SHA-256 checksum. Verify with `shasum -a 256 -c SSH-Island.dmg.sha256` in the download directory.
- This package is **ad hoc signed, not Developer ID signed or notarized**. Gatekeeper may block the downloaded app. If you trust this release, try opening it once, then use **System Settings → Privacy & Security → Open Anyway** if macOS offers that action. Alternatively, build from source using `./scripts/build.sh`. Do not disable Gatekeeper globally.
- macOS requests Automation permission to control Terminal on the first connection. No Accessibility or Full Disk Access permission is needed.

## Included

- SSH alias discovery with recursive Includes, globbing and config refresh.
- Favorites, recent hosts, search and keyboard navigation.
- Menu-bar fallback, Settings, configurable global shortcut and Launch at Login.
- A new Terminal session for each connection; existing OpenSSH configuration remains the source of truth.

The notch is a public-API overlay. Physical display changes, full-screen Spaces and interactive accessibility/login behavior still need manual validation on each setup. See the README and `docs/VALIDATION.md` for limits and checks performed. This release does not claim Apple notarization.

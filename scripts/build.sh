#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
configuration="${1:-release}"
swift build -c "$configuration" --arch arm64
bin_path="$(swift build -c "$configuration" --arch arm64 --show-bin-path)"
app_path="$PWD/build/SSH Island.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$bin_path/SSHIsland" "$app_path/Contents/MacOS/SSHIsland"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then cp Resources/AppIcon.icns "$app_path/Contents/Resources/"; fi
codesign --force --options runtime --entitlements Resources/SSHIsland.entitlements --sign - "$app_path"
print -r -- "$app_path"

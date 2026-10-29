#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
: "${SIGNING_IDENTITY:?Set SIGNING_IDENTITY to your Developer ID Application identity}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile}"
./scripts/test.sh
./scripts/build.sh
app_path="$PWD/build/SSH Island.app"
codesign --force --options runtime --timestamp --entitlements Resources/SSHIsland.entitlements --sign "$SIGNING_IDENTITY" "$app_path"
codesign --verify --strict --verbose=2 "$app_path"
ditto -c -k --keepParent "$app_path" build/SSH-Island-notarization.zip
xcrun notarytool submit build/SSH-Island-notarization.zip --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$app_path"
stage_path="$(mktemp -d "${TMPDIR:-/tmp}/ssh-island-release.XXXXXX")"
trap 'rm -rf "$stage_path"' EXIT
ditto "$app_path" "$stage_path/SSH Island.app"
ln -s /Applications "$stage_path/Applications"
hdiutil create -volname 'SSH Island' -srcfolder "$stage_path" -ov -format UDZO build/SSH-Island.dmg
codesign --timestamp --sign "$SIGNING_IDENTITY" build/SSH-Island.dmg
xcrun notarytool submit build/SSH-Island.dmg --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple build/SSH-Island.dmg
shasum -a 256 build/SSH-Island.dmg > build/SSH-Island.dmg.sha256

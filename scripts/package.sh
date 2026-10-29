#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
./scripts/test.sh
./scripts/build.sh
stage_path="$(mktemp -d "${TMPDIR:-/tmp}/ssh-island-dmg.XXXXXX")"
trap 'rm -rf "$stage_path"' EXIT
 ditto "build/SSH Island.app" "$stage_path/SSH Island.app"
ln -s /Applications "$stage_path/Applications"
hdiutil create -volname 'SSH Island' -srcfolder "$stage_path" -ov -format UDZO "build/SSH-Island.dmg"

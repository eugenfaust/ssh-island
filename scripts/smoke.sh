#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
./scripts/build.sh
SSH_ISLAND_SMOKE_DIR="$PWD/build/smoke" "build/SSH Island.app/Contents/MacOS/SSHIsland" --self-test
cat build/smoke/smoke.txt
if rg '^FAIL' build/smoke/smoke.txt; then exit 1; fi

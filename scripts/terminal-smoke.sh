#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
./scripts/build.sh
mkdir -p build/terminal-smoke
rm -f build/terminal-smoke/result.txt build/terminal-smoke/terminal-output.txt
# LaunchServices establishes the app as the responsible TCC identity; direct exec inherits the IDE's identity.
open -n -W "$PWD/build/SSH Island.app" --args --terminal-smoke --smoke-output "$PWD/build/terminal-smoke"
cat build/terminal-smoke/result.txt
if rg '^FAIL' build/terminal-smoke/result.txt; then exit 1; fi

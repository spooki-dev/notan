#!/usr/bin/env bash
# Prints every file that goes inside the .love, one repo-relative path per line.
#
#   scripts/love-filelist.sh            # the shipped file list
#
# scripts/release.sh zips this list into the .love and the CI workflow checks
# the same list, so there is one definition of "what ships" and the build and
# the test can never disagree about it.
#
# The list comes from `git ls-files`, so an untracked file is never packaged:
# the sample photos under assets/sample-photos/ are local-only and used to be
# shipped to players by accident.
set -euo pipefail
cd "$(dirname "$0")/.."

# Extended regexes matched against the whole repo-relative path. Anchor every
# one of them. love-release, which used to build the .love, matched its
# exclude list as unanchored Lua patterns, so `-x engine/dev` also matched
# engine/device/ and shipped a .love that died on `require "engine.device.backends"`.
EXCLUDE=(
  '^\.'                 # .github, .vscode, .claude, .githooks, .luarc.json, .gitignore
  '^docs/'
  '^scripts/'
  '^designs/'
  '^examples/'
  '^releases/'
  '^assets/generated/'  # marketing art: baked into the packages, not read by the game
  '^engine/dev/'        # the MCP bridge; engine/Game.lua requires it through pcall
  '\.md$'
)

pattern=$(IFS='|'; printf '%s' "${EXCLUDE[*]}")
git ls-files | grep -vE "$pattern"

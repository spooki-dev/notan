#!/usr/bin/env bash
# Resolves every `require "a.b.c"` and every file path literal in a tree of
# Lua, and fails if one of them points at a file that is not there.
#
#   scripts/check-requires.sh                 # the files scripts/love-filelist.sh ships
#   scripts/check-requires.sh path/to/tree    # an unpacked .love, or any directory
#
# This is the regression test for #3: `-x engine/dev` dropped engine/device/
# out of the .love, so the game booted to "module 'engine.device.backends' not
# found" while the working tree was perfectly fine. Only a check against the
# packaged file set catches that, which is why the no-argument form builds the
# shipped list rather than looking at the repo.
set -euo pipefail
cd "$(dirname "$0")/.."

ROOT="${1:-}"
CLEANUP=""
if [[ -z "$ROOT" ]]; then
  ROOT=$(mktemp -d)
  CLEANUP="$ROOT"
  trap 'rm -rf "$CLEANUP"' EXIT
  scripts/love-filelist.sh | tar -cf - -T - | tar -xf - -C "$ROOT"
  WHAT="the shipped file list"
else
  WHAT="$ROOT"
fi
[[ -d "$ROOT" ]] || { echo "not a directory: $ROOT" >&2; exit 1; }

# Modules the Lua or LÖVE runtime provides, so no file backs them. Anything
# under love.* is a LÖVE module; lldebugger comes from the VS Code debugger
# and is only required when LOCAL_LUA_DEBUGGER_VSCODE is set.
is_builtin() {
  case "$1" in
    love|love.*|lldebugger|string|table|math|os|io|debug|coroutine|package|bit|jit|ffi) return 0 ;;
    *) return 1 ;;
  esac
}

# file<TAB>line<TAB>kind<TAB>target, for every require and path literal.
# A `require` reached through pcall is optional by construction (that is how
# engine/Game.lua reaches the dev-only MCP bridge), so it is skipped.
references() {
  find "$ROOT" -type f -name '*.lua' -print0 | sort -z | xargs -0 awk '
    {
      line = $0
      if (line ~ /pcall[ \t]*\([ \t]*require/) next
      # Walk the line so a reference after a `--` can be ignored as a comment.
      rest = line
      offset = 0
      while (match(rest, /require[ \t]*\(?[ \t]*"[A-Za-z0-9_.]+"|"[A-Za-z0-9_][A-Za-z0-9_.\/-]*\/[A-Za-z0-9_.\/-]+\.(lua|png|jpg|ttf|otf|ogg|wav|mp3|glsl|frag|vert)"/)) {
        tok = substr(rest, RSTART, RLENGTH)
        before = substr(line, 1, offset + RSTART - 1)
        offset += RSTART + RLENGTH - 1
        rest = substr(rest, RSTART + RLENGTH)
        if (index(before, "--") > 0) continue
        if (tok ~ /^require/) {
          match(tok, /"[A-Za-z0-9_.]+"/)
          print FILENAME "\t" FNR "\tmodule\t" substr(tok, RSTART + 1, RLENGTH - 2)
        } else {
          print FILENAME "\t" FNR "\tfile\t" substr(tok, 2, length(tok) - 2)
        }
      }
    }
  '
}

status=0
count=0
while IFS=$'\t' read -r file line kind target; do
  count=$((count + 1))
  if [[ "$kind" == module ]]; then
    is_builtin "$target" && continue
    path=${target//.//}
    [[ -f "$ROOT/$path.lua" || -f "$ROOT/$path/init.lua" ]] && continue
    echo "${file#"$ROOT"/}:$line: require \"$target\" resolves to nothing in $WHAT" >&2
  else
    [[ -f "$ROOT/$target" ]] && continue
    echo "${file#"$ROOT"/}:$line: \"$target\" is not in $WHAT" >&2
  fi
  status=1
done < <(references)

[[ $count -gt 0 ]] || { echo "no Lua references found under $ROOT — wrong directory?" >&2; exit 1; }
[[ $status -eq 0 ]] && echo "requires and asset paths OK ($count references in $WHAT)"
exit $status

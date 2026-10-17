#!/usr/bin/env bash
# Builds and publishes the game to itch.io. Fill in the variables below first.
#
#   scripts/release.sh            # export assets, build all platforms, push with butler
#   scripts/release.sh --no-push  # everything except the butler pushes
#
# Steps: regenerate marketing art (love . --export-assets) -> .love via
# love-release -> Mac .app and Windows .exe packaged from the official LÖVE
# runtime with the generated icon baked in -> web build via love.js with a
# favicon -> butler push per channel -> checklist of page images to upload
# by hand (itch.io has no API for cover/screenshot images).
set -euo pipefail
cd "$(dirname "$0")/.."

TITLE="Notan"
PKG=notan
UTI=com.spooki.notan
AUTHOR="George Butter"
ITCH=your-itch-username/notan
ITCH_EDIT_URL="https://your-itch-username.itch.io/notan/edit"
LOVE=/Applications/love.app/Contents/MacOS/love
export PATH="$(dirname "$LOVE"):$PATH"   # love-release shells out to `love`
# love-release only supports LÖVE <= 11.3, so Mac/Windows packages are built
# here from the official runtime zips for the version the game targets.
LOVE_RUNTIME_VERSION=11.5
RUNTIME_CACHE="$HOME/.cache/love-release"
OUT=releases/$PKG
GEN=assets/generated
SHA=$(git rev-parse --short HEAD)
PUSH=1
[[ "${1:-}" == "--no-push" ]] && PUSH=0

for tool in "$LOVE" iconutil sips plutil codesign zip unzip curl node npm love-release love.js butler perl; do
  command -v "$tool" >/dev/null || { echo "missing tool: $tool" >&2; exit 1; }
done

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

step() { printf '\n==> %s\n' "$*"; }

step "Export marketing assets"
"$LOVE" . --export-assets | grep '^exported'
for name in icon favicon cover social wide logo; do
  [[ -f "$GEN/$name.png" ]] || { echo "missing $GEN/$name.png" >&2; exit 1; }
done

step "Build .love"
rm -rf "$OUT"
mkdir -p "$OUT"
love-release -t "$TITLE" -a "$AUTHOR" --uti "$UTI" -p "$PKG" \
  -x DEV -x .git -x releases -x designs -x docs -x .aider -x .claude -x .vscode \
  -x engine/dev -x .md -x scripts -x assets/generated -x init.sh -x examples \
  "$OUT" . >/dev/null
LOVEFILE="$OUT/$TITLE.love"
[[ -f "$LOVEFILE" ]] || { echo "love-release did not produce $LOVEFILE" >&2; exit 1; }

step "Check shipped Lua parses under Lua 5.1 (love.js runtime)"
# love.js runs PUC Lua 5.1, not LuaJIT. Check the exact files inside the .love
# so the web build cannot ship something that only LuaJIT accepts (e.g. goto).
unzip -q "$LOVEFILE" -d "$WORK/lovecheck"
(cd "$WORK/lovecheck" && "$OLDPWD/scripts/lint-lua51.sh" $(find . -name '*.lua' | sed 's|^\./||'))

step "Fetch LÖVE $LOVE_RUNTIME_VERSION runtimes"
mkdir -p "$RUNTIME_CACHE"
for platform in macos win32 win64; do
  zipfile="$RUNTIME_CACHE/love-$LOVE_RUNTIME_VERSION-$platform.zip"
  [[ -f "$zipfile" ]] || curl -fsSL -o "$zipfile" \
    "https://github.com/love2d/love/releases/download/$LOVE_RUNTIME_VERSION/love-$LOVE_RUNTIME_VERSION-$platform.zip"
done

step "Build .icns"
ICONSET="$WORK/$PKG.iconset"
mkdir "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$GEN/icon.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) "$GEN/icon.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$WORK/$PKG.icns"

step "Package macOS app"
unzip -q "$RUNTIME_CACHE/love-$LOVE_RUNTIME_VERSION-macos.zip" -d "$WORK/mac"
APP="$WORK/mac/$TITLE.app"
mv "$WORK/mac/love.app" "$APP"
cp "$LOVEFILE" "$APP/Contents/Resources/"
cp "$WORK/$PKG.icns" "$APP/Contents/Resources/OS X AppIcon.icns"
cp "$WORK/$PKG.icns" "$APP/Contents/Resources/GameIcon.icns"
PLIST="$APP/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "$UTI" "$PLIST"
plutil -replace CFBundleName -string "$TITLE" "$PLIST"
plutil -replace CFBundleDisplayName -string "$TITLE" "$PLIST" 2>/dev/null || true
# With CFBundleIconName present macOS reads the icon from Assets.car, not the .icns.
plutil -remove CFBundleIconName "$PLIST" 2>/dev/null || true
plutil -remove UTExportedTypeDeclarations "$PLIST" 2>/dev/null || true
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "warning: ad-hoc codesign failed" >&2
(cd "$WORK/mac" && zip -qry "$OLDPWD/$OUT/$TITLE-macos.zip" "$TITLE.app")

step "Package Windows exes"
(cd scripts && npm install --silent --no-audit --no-fund)
mkdir "$WORK/ico"
for size in 16 24 32 48 64 128 256; do
  sips -z "$size" "$size" "$GEN/icon.png" --out "$WORK/ico/$size.png" >/dev/null
done
for arch in 32 64; do
  DIR="$WORK/win$arch"
  unzip -q "$RUNTIME_CACHE/love-$LOVE_RUNTIME_VERSION-win$arch.zip" -d "$DIR"
  SRC="$DIR/love-$LOVE_RUNTIME_VERSION-win$arch"
  [[ -f "$SRC/love.exe" ]] || { echo "unexpected layout in win$arch runtime zip" >&2; ls "$DIR" >&2; exit 1; }
  node scripts/patch-win-icon.mjs "$SRC/love.exe" "$DIR/love-icon.exe" "$WORK"/ico/*.png
  # Same trick love-release uses: the .love zip is appended to the exe and
  # found via its end-of-central-directory record.
  cat "$DIR/love-icon.exe" "$LOVEFILE" > "$SRC/$PKG.exe"
  rm -f "$SRC/love.exe" "$SRC/lovec.exe" "$SRC/readme.txt" "$SRC/changes.txt" "$SRC/love.ico" "$SRC/game.ico"
  mv "$SRC" "$DIR/$TITLE-win$arch"
  (cd "$DIR" && zip -qr "$OLDPWD/$OUT/$TITLE-win$arch.zip" "$TITLE-win$arch")
done

step "Build web"
love.js -c -t "$TITLE" "$LOVEFILE" "$OUT/web" >/dev/null
# Swap the stock love.js page (heading, footer, "Powered by" text) for our bare
# template in scripts/web/, keeping love.js's game.js/love.js/love.wasm/game.data.
cp -R scripts/web/. "$OUT/web/"
rm -f "$OUT/web/theme/bg.png"
TITLE="$TITLE" perl -pi -e 's/\{\{TITLE\}\}/$ENV{TITLE}/g' "$OUT/web/index.html"
cp "$GEN/favicon.png" "$OUT/web/theme/favicon.png"
grep -q 'theme/favicon.png' "$OUT/web/index.html" || { echo "favicon link missing from web page" >&2; exit 1; }
grep -q '{{' "$OUT/web/index.html" && { echo "unsubstituted placeholder in web page" >&2; exit 1; }

# butler unpacks zip uploads, and a .love is a zip, so push it from a folder.
mkdir -p "$OUT/love"
cp "$LOVEFILE" "$OUT/love/"

if [[ $PUSH -eq 1 ]]; then
  step "Push to itch.io ($ITCH @ $SHA)"
  butler push "$OUT/$TITLE-macos.zip" "${ITCH}:mac"        --userversion "$SHA"
  butler push "$OUT/$TITLE-win64.zip" "${ITCH}:windows"    --userversion "$SHA"
  butler push "$OUT/$TITLE-win32.zip" "${ITCH}:windows-32" --userversion "$SHA"
  butler push "$OUT/web"              "${ITCH}:web"        --userversion "$SHA"
  butler push "$OUT/love"             "${ITCH}:love"       --userversion "$SHA"
  butler status "$ITCH"
else
  step "Skipping butler push (--no-push)"
fi

cat <<MSG

Builds are in $OUT/. itch.io cannot receive page images via butler or its API,
so upload these by hand on the edit page:

  $GEN/cover.png    630x500    Edit game -> Cover image
  $GEN/wide.png     1920x1080  Edit theme -> Banner / background image
  $GEN/social.png   1200x630   Devlogs and social posts
  $GEN/logo.png     1600x400   Press kit / transparent banner
  $GEN/icon.png     1024x1024  Store listings / press kit
  assets/screenshots/*.png     Edit game -> Screenshots

First release only: on the edit page tick "This file will be played in the
browser" on the *web* channel upload (not the .love one, which has no
index.html), set its viewport to 1280x720, and set the page kind to HTML.
MSG
if [[ $PUSH -eq 1 ]]; then
  open "$ITCH_EDIT_URL" 2>/dev/null || echo "Edit page: $ITCH_EDIT_URL"
fi

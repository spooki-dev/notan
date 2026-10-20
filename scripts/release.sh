#!/usr/bin/env bash
# Builds Notan and publishes it as a GitHub release. Fill in the variables below
# first, and bump VERSION for each release (the tag must not already exist).
#
#   scripts/release.sh            # export assets, build every platform, publish the release
#   scripts/release.sh --no-push  # everything except the gh release
#   VERSION=0.2.0 scripts/release.sh
#
# Steps: regenerate marketing art (love . --export-assets) -> .love zipped from
# scripts/love-filelist.sh -> a macOS .dmg and a Windows installer .exe built
# from the official LÖVE runtime with the generated icon baked in -> gh release
# create with every download attached. spookidev.com/notan links at
# /releases/latest/download/, so the page needs no change when a release goes
# out.
set -euo pipefail
cd "$(dirname "$0")/.."

TITLE="Notan"
PKG=notan
UTI=com.spooki.notan
AUTHOR="George Butter"
REPO=spooki-dev/notan
# Bump for every release; the tag is v$VERSION and gh refuses an existing one.
VERSION="${VERSION:-0.1.0}"
LOVE=/Applications/love.app/Contents/MacOS/love
# Mac/Windows packages are built here from the official runtime zips for the
# version the game targets.
LOVE_RUNTIME_VERSION=11.5
RUNTIME_CACHE="$HOME/.cache/love-release"
OUT=releases/$PKG
GEN=assets/generated
SHA=$(git rev-parse --short HEAD)
PUSH=1
[[ "${1:-}" == "--no-push" ]] && PUSH=0

for tool in "$LOVE" iconutil sips plutil codesign hdiutil makensis zip unzip curl node npm gh; do
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
# A .love is just a zip with main.lua at the root. scripts/love-filelist.sh
# decides what goes in; this used to be love-release, whose exclude list was
# matched as unanchored Lua patterns, so "-x engine/dev" quietly took
# engine/device/ with it and shipped a build that could not boot.
rm -rf "$OUT"
mkdir -p "$OUT"
LOVEFILE="$OUT/$TITLE.love"
scripts/love-filelist.sh > "$WORK/filelist"
[[ -s "$WORK/filelist" ]] || { echo "scripts/love-filelist.sh produced nothing" >&2; exit 1; }
grep -qx 'main.lua' "$WORK/filelist" || { echo "main.lua is not in the .love file list" >&2; exit 1; }
zip -q -X -@ "$PWD/$LOVEFILE" < "$WORK/filelist"
echo "packaged $(wc -l < "$WORK/filelist" | tr -d ' ') files into $LOVEFILE"

step "Check the .love is complete and parses under Lua 5.1"
# Check the exact files inside the .love, not the working tree: the engine is
# kept inside the Lua 5.1 subset LuaJIT and PUC Lua share (.luarc.json and the
# pre-commit hook enforce that too), and every require and asset path has to
# point at a file that actually got packaged.
unzip -q "$LOVEFILE" -d "$WORK/lovecheck"
(cd "$WORK/lovecheck" && "$OLDPWD/scripts/lint-lua51.sh" $(find . -name '*.lua' | sed 's|^\./||'))
scripts/check-requires.sh "$WORK/lovecheck"

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

step "Build the .dmg"
# A disk image rather than a zip: it mounts on double-click and the
# /Applications symlink makes installing the obvious drag, instead of leaving
# an .app loose in ~/Downloads where macOS quarantines it hardest.
DMG="$OUT/$TITLE-macos.dmg"
STAGE="$WORK/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$TITLE.app"   # ditto, not cp: keeps the signature intact
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "$TITLE" -srcfolder "$STAGE" -ov -format UDZO -fs HFS+ "$DMG"
codesign --force --sign - "$DMG" 2>/dev/null || echo "warning: ad-hoc codesign of the dmg failed" >&2

step "Package Windows installers"
(cd scripts && npm install --silent --no-audit --no-fund)
mkdir "$WORK/ico"
for size in 16 24 32 48 64 128 256; do
  sips -z "$size" "$size" "$GEN/icon.png" --out "$WORK/ico/$size.png" >/dev/null
done
node scripts/png-to-ico.mjs "$WORK/$PKG.ico" "$WORK"/ico/*.png >/dev/null
for arch in 32 64; do
  DIR="$WORK/win$arch"
  unzip -q "$RUNTIME_CACHE/love-$LOVE_RUNTIME_VERSION-win$arch.zip" -d "$DIR"
  SRC="$DIR/love-$LOVE_RUNTIME_VERSION-win$arch"
  [[ -f "$SRC/love.exe" ]] || { echo "unexpected layout in win$arch runtime zip" >&2; ls "$DIR" >&2; exit 1; }
  node scripts/patch-win-icon.mjs "$SRC/love.exe" "$DIR/love-icon.exe" "$WORK"/ico/*.png
  # The .love zip is appended to the exe and found via its end-of-central-
  # directory record, which is how LÖVE finds a fused game.
  cat "$DIR/love-icon.exe" "$LOVEFILE" > "$SRC/$PKG.exe"
  rm -f "$SRC/love.exe" "$SRC/lovec.exe" "$SRC/readme.txt" "$SRC/changes.txt" "$SRC/love.ico" "$SRC/game.ico"
  # An installer rather than a folder in a zip: the game needs its DLLs
  # beside it, and a zip asks a beginner to understand that before it will
  # run. NSIS cross-builds from macOS; see scripts/windows-installer.nsi for
  # why the install is per-user.
  makensis -V2 \
    "-DTITLE=$TITLE" "-DPKG=$PKG" "-DVERSION=$VERSION" "-DARCH=$arch" \
    "-DSRCDIR=$SRC" "-DICON=$WORK/$PKG.ico" \
    "-DOUTFILE=$PWD/$OUT/$TITLE-win$arch-setup.exe" \
    scripts/windows-installer.nsi
done

if [[ $PUSH -eq 1 ]]; then
  step "Publish release v$VERSION to $REPO"
  gh release create "v$VERSION" \
    --repo "$REPO" \
    --title "$TITLE $VERSION" \
    --notes "Built from $SHA. The macOS app and the Windows installers are unsigned: see the install notes at https://spookidev.com/notan#install." \
    "$DMG#$TITLE for macOS (.dmg)" \
    "$OUT/$TITLE-win64-setup.exe#$TITLE for Windows, 64-bit (installer)" \
    "$OUT/$TITLE-win32-setup.exe#$TITLE for Windows, 32-bit (installer)" \
    "$LOVEFILE#$TITLE.love (any OS with LÖVE $LOVE_RUNTIME_VERSION)"
  gh release view "v$VERSION" --repo "$REPO" --web
else
  step "Skipping the GitHub release (--no-push)"
fi

cat <<MSG

Builds are in $OUT/.

The download buttons on https://spookidev.com/notan point at
https://github.com/$REPO/releases/latest/download/<file>, which GitHub
redirects to the newest release, so the site needs no change when you ship.

Marketing art, if you want it on the page or in a readme:

  $GEN/cover.png    630x500
  $GEN/wide.png     1920x1080
  $GEN/social.png   1200x630
  $GEN/logo.png     1600x400
  $GEN/icon.png     1024x1024
MSG

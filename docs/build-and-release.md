---
title: Build and Release
description: Keeping the code Lua 5.1 compatible for the web build, and running scripts/release.sh to package Mac, Windows, web and .love builds and push them to itch.io.
order: 8
---

One script, `scripts/release.sh`, does the whole release: it regenerates the marketing art, builds the `.love`, packages Mac and Windows from the official LÖVE 11.5 runtime with the generated icon baked in, builds the web version with love.js and a favicon, pushes every channel to itch.io with butler, then prints the page images you still have to upload by hand. Before any of that matters, the code has to parse under Lua 5.1, because the web build does not run on LuaJIT, and every module it reaches for has to be inside the `.love`.

## Lua 5.1 compatibility

Desktop LÖVE runs LuaJIT, but love.js runs the game on PUC Lua 5.1. Game and engine code must stay within the subset both accept:

- no `goto` or `::label::`
- no `ffi`, `jit` or `bit` modules outside `engine/dev`
- no `table.pack`, `table.unpack` or `math.tointeger`
- no `\z` or `\x` string escapes

Three layers enforce this:

| Layer | What it does |
|---|---|
| `.luarc.json` | Sets `Lua.runtime.version` to `Lua 5.1`, so LuaLS flags the constructs above as syntax errors in the editor. |
| `scripts/lint-lua51.sh [files...]` | Parses files with a real `luac` 5.1 (`luac -p`, no execution). With no arguments it checks every tracked `.lua` file (`git ls-files '*.lua'`). |
| `.githooks/pre-commit` | Runs the lint over staged `.lua` files and blocks the commit on a parse error. Enable it once per clone with `git config core.hooksPath .githooks`. |
| `.github/workflows/ci.yml` | Runs the lint and `scripts/check-requires.sh` on every push and pull request. |

Homebrew no longer ships `lua@5.1`, so on first run `scripts/lint-lua51.sh` downloads the official Lua 5.1.5 tarball and builds it into `~/.cache/love-release/` (override the location with `LOVE_RELEASE_CACHE`). `scripts/release.sh` also runs the lint over the exact files inside the built `.love`, so the web build cannot ship something only LuaJIT accepts.

```sh
scripts/lint-lua51.sh                      # every tracked .lua file
scripts/lint-lua51.sh engine/ui/UIBox.lua  # specific files
git config core.hooksPath .githooks        # enable the pre-commit hook
```

## Prerequisites

`scripts/release.sh` checks for each of these at the start and exits if one is missing.

| Tool | Where it comes from | Used for |
|---|---|---|
| `love` | `/Applications/love.app/Contents/MacOS/love` (the `LOVE` variable) | `love . --export-assets` |
| `love.js` | Installed separately | The web build |
| `butler` | https://itch.io/docs/butler/ (the Homebrew `butler` cask is an unrelated app) | Pushing channels to itch.io; run `butler login` once in a real terminal |
| `node`, `npm` | Node.js | `scripts/patch-win-icon.mjs`, with dependencies from `scripts/package.json` (`pe-library`, `png-to-ico`, `resedit`) |
| `iconutil`, `sips`, `plutil`, `codesign` | macOS | `.icns` creation, icon resizing, `Info.plist` edits, ad-hoc signing |
| `zip`, `unzip`, `curl`, `perl` | macOS | Packaging, fetching runtimes, `{{TITLE}}` substitution |

## Configuring the script

Fill in the variables at the top of `scripts/release.sh`. `init.sh` rewrites them when scaffolding a new game.

| Variable | Default | Meaning |
|---|---|---|
| `TITLE` | `"New Game"` | Display name; names the `.love`, the `.app` and the zips |
| `PKG` | `newgame` | Package slug; names `releases/<PKG>/` and the Windows `.exe` |
| `UTI` | `com.example.newgame` | Bundle identifier written to `CFBundleIdentifier` |
| `AUTHOR` | `"Your Name"` | Release author |
| `ITCH` | `your-itch-username/your-game-slug` | butler target; channels are appended as `${ITCH}:mac` and so on |
| `ITCH_EDIT_URL` | `https://your-itch-username.itch.io/your-game-slug/edit` | Opened after a push |

Other values near the top are not meant to change per game: `LOVE_RUNTIME_VERSION=11.5`, `RUNTIME_CACHE="$HOME/.cache/love-release"`, `OUT=releases/$PKG`, `GEN=assets/generated`.

## Running a release

```sh
scripts/release.sh            # full release: build everything and push to itch.io
scripts/release.sh --no-push  # everything except the butler pushes
love . --export-assets        # only regenerate assets/generated/*.png
```

The script runs with `set -euo pipefail` from the repo root and uses a temporary work directory that is removed on exit. A full run does the following, in order:

1. **Export marketing assets.** Runs `love . --export-assets` and checks that `icon`, `favicon`, `cover`, `social`, `wide` and `logo` PNGs exist in `assets/generated/` (see `assets.md`).
2. **Build `.love`.** Empties `releases/<PKG>/`, then zips the paths `scripts/love-filelist.sh` prints into `releases/<PKG>/<TITLE>.love`. A `.love` is only a zip with `main.lua` at the root, so there is nothing else to it.
3. **Check the `.love`.** Unzips it, runs `scripts/lint-lua51.sh` over every `.lua` inside, then `scripts/check-requires.sh` over the unpacked tree.
4. **Fetch runtimes.** Downloads `love-11.5-macos.zip`, `love-11.5-win32.zip` and `love-11.5-win64.zip` from the LÖVE GitHub releases into `~/.cache/love-release/` if not already cached.
5. **Build `.icns`.** Resizes `icon.png` with `sips` to 16 through 512 plus `@2x` variants and runs `iconutil -c icns`.
6. **Package macOS.** Renames `love.app` to `<TITLE>.app`, copies the `.love` into `Contents/Resources/`, writes the `.icns` as `OS X AppIcon.icns` and `GameIcon.icns`, sets `CFBundleIdentifier`, `CFBundleName` and `CFBundleDisplayName`, removes `CFBundleIconName` and `UTExportedTypeDeclarations`, ad-hoc signs with `codesign --force --deep --sign -`, and zips to `<TITLE>-macos.zip`.
7. **Package Windows.** Runs `npm install` in `scripts/`, resizes `icon.png` to 16 through 256, and for each of `win32` and `win64` patches the icon into `love.exe` with `node scripts/patch-win-icon.mjs`, appends the `.love` to the exe as `<PKG>.exe`, removes `love.exe`, `lovec.exe`, the readmes and the stock `.ico` files, and zips to `<TITLE>-win32.zip` and `<TITLE>-win64.zip`.
8. **Build web.** Runs `love.js -c -t "$TITLE"` into `releases/<PKG>/web/`, copies `scripts/web/` over the output, deletes `theme/bg.png`, substitutes `{{TITLE}}`, copies `favicon.png` to `theme/favicon.png`, and fails if the favicon link or an unsubstituted `{{` placeholder is found.
9. **Stage the `.love`.** Copies it into `releases/<PKG>/love/`, because butler unpacks zip uploads and a `.love` is a zip.
10. **Push** (skipped with `--no-push`). `butler push` for `mac`, `windows`, `windows-32`, `web` and `love` channels, each with `--userversion` set to the short git SHA, then `butler status "$ITCH"`.
11. **Checklist.** Prints the page images to upload by hand and, after a push, opens `ITCH_EDIT_URL`.

### Outputs

Everything lands in `releases/<PKG>/`, which is git-ignored:

| Path | Contents |
|---|---|
| `<TITLE>.love` | The game archive |
| `<TITLE>-macos.zip` | `<TITLE>.app` for macOS |
| `<TITLE>-win32.zip`, `<TITLE>-win64.zip` | `<TITLE>-win32/` and `<TITLE>-win64/` folders with `<PKG>.exe` and the LÖVE DLLs |
| `web/` | love.js output plus the template page |
| `love/<TITLE>.love` | Folder copy pushed to the `love` channel |

### What ships and what does not

`scripts/love-filelist.sh` is the single definition of the contents, and `scripts/release.sh` and CI both read it, so the build and the test can never disagree about what is in there. It starts from `git ls-files` — an untracked file is never packaged, which is why the local-only photos in `assets/sample-photos/` stay on your machine — and drops dotfiles, `docs/`, `scripts/`, `designs/`, `examples/`, `releases/`, `assets/generated/`, `engine/dev/` and every `.md`.

Dropping `engine/dev/` removes the MCP bridge; `engine/Game.lua` requires it through `pcall`, so a shipped build silently skips it. Hot reload and the bridge are otherwise switched by `env = "dev"` in `main.lua`.

Every exclude is an **anchored** extended regex matched against the whole path, and it has to stay that way. The script that this replaced, `love-release`, matched its excludes as unanchored Lua patterns, so `-x engine/dev` also matched `engine/device/` and shipped a `.love` that died on startup with `module 'engine.device.backends' not found` while the working tree was perfectly healthy.

### Checking the contents

```sh
scripts/love-filelist.sh              # what goes in the .love
scripts/check-requires.sh             # resolve every reference against that list
scripts/check-requires.sh some/dir    # ...or against an unpacked .love
```

`scripts/check-requires.sh` reads every `require "a.b.c"` and every quoted file path (`"assets/fonts/PixelOperator8.ttf"`, `"engine/device/threads/pickerThread.lua"`) out of the shipped Lua and fails if one of them points at a file that is not there. A `require` reached through `pcall` is treated as optional, because that is how the engine reaches the dev-only bridge. With no argument it builds the shipped list itself, which is the form CI runs: a missing module only shows up against the packaged file set, never against the working tree.

## Platform notes

- Mac and Windows packages are assembled from the official 11.5 runtime zips rather than by a packaging tool, so the shipped runtime is exactly the version the game targets.
- The Windows icon is replaced inside the PE resource table by `scripts/patch-win-icon.mjs` (`node scripts/patch-win-icon.mjs <in.exe> <out.exe> <png> [<png>...]`), pure JavaScript via `pe-library` and `resedit`, so no Windows tooling is needed on macOS. The `.love` is then appended to the exe, which is how LÖVE finds a fused game.
- The Mac icon is an `.icns` built with `iconutil`. With `CFBundleIconName` present macOS reads the icon from `Assets.car`, so the script removes that key.
- Signing is ad-hoc; a failure prints a warning and continues.

## The web page

love.js generates a page with a heading, footer and "Powered by" text. The script replaces it with the template in `scripts/web/`:

- `index.html` has a `{{TITLE}}` placeholder, links `theme/love.css` and `theme/favicon.png`, draws loading status text on a `loadingCanvas`, stops space and the arrow keys scrolling the page, and passes `Module.arguments = ["./game.love"]` to love.js. It also dispatches a synthetic `beforeunload` on `pagehide`, when the tab is hidden and every 10 seconds so love.js flushes the IndexedDB save directory.
- `theme/love.css` centres the canvas on `#000000` with no border or padding, so mouse coordinates do not drift.

love.js's own `game.js`, `love.js`, `love.wasm` and `game.data` are kept. Change the colours in `theme/love.css` and the loading text in `index.html` to suit the game.

## itch.io checklist

butler can only push build channels, and itch.io has no API for page images, so after a push:

1. Upload `assets/generated/cover.png` (630x500) under Edit game, Cover image.
2. Upload `assets/generated/wide.png` (1920x1080) under Edit theme, Banner or background image.
3. Keep `social.png` (1200x630) for devlogs and social posts, `logo.png` (1600x400, transparent) for press kits, and `icon.png` (1024x1024) for store listings.
4. Upload screenshots under Edit game, Screenshots. The script's message suggests keeping them in `assets/screenshots/`.

First release only, on the edit page: tick "This file will be played in the browser" on the **web** channel upload, set its viewport to 1280x720, and set the page kind to HTML. Ticking the flag on the `.love` upload fails with "Failed to find index.html". Run `butler login` once in a real terminal before the first push.

# Notan

A desktop image tool for painters. Open a photo and stack GPU effects over it — blur, levels, saturation, posterise — so its values read as flat shapes before you paint them. *Notan* (濃淡) is the Japanese principle of designing a picture through its masses of light and dark, which is what the effect chain leaves behind. Built on the [spooki-love](https://github.com/spooki-dev/spooki-love) LÖVE (Love2D) 11.5 engine template.

## Run

```sh
# love is not on PATH on macOS:
/Applications/love.app/Contents/MacOS/love .
/Applications/love.app/Contents/MacOS/love . ~/pictures/study.jpg   # open straight onto an image
```

Drag an image onto the window, or press `O`. Then:

| Key | |
|---|---|
| `O` | open an image |
| `E` | export the processed image as a PNG next to the source |
| `TAB` | hold to see the original |
| `0` / `1` | fit to window / 100% |
| `G` | toggle the composition grid |
| `R` | reset the effects |
| `H` | hide the panel |
| `C` | key bindings |

Scroll to zoom, drag to pan. Click or drag the sliders; the arrow keys walk the panel and adjust the selected row. Effect settings are remembered between sessions.

Hot reload is on in dev: saved edits under `engine/`, `scenes/`, `gameObjects/`, `effects/`, `app/`, `constants/` and `state/` reload automatically (backtick forces it). A dev MCP bridge listens on port 12345.

## Develop

- The app is `scenes/Viewer.lua` (view transform, loading, export) plus `gameObjects/ControlPanel.lua` (the sliders).
- Effects are data: add an entry to `effects/init.lua` with its GLSL and parameters and it appears in the panel. `effects/Pipeline.lua` runs the chain over two canvases.
- Files outside LÖVE's sandbox go through `app/imageIO.lua`; the OS file picker runs on `app/dialogThread.lua` so the window keeps drawing.
- Scenes live in `scenes/` and are registered in `main.lua` (`Preload` first). See `docs/scenes.md`.
- `engine/` is the shared engine. Configure it through the `Game` table in `main.lua` rather than editing it.
- The web build runs on Lua 5.1 (love.js), so avoid `goto` and LuaJIT-only modules. `scripts/lint-lua51.sh` checks every tracked Lua file; enable the pre-commit hook with `git config core.hooksPath .githooks`.
- Marketing art in `assets/generated/` is rendered from `scenes/assets/*.lua` by `love . --export-assets`.

## Release

```sh
scripts/release.sh            # export assets, build Mac/Windows/web/.love, push to itch.io
scripts/release.sh --no-push  # build only; artefacts land in releases/notan/
/Applications/love.app/Contents/MacOS/love . --export-assets       # regenerate assets/generated/*.png only
```

`TITLE`, `PKG`, `UTI`, `AUTHOR` and `ITCH` are set at the top of `scripts/release.sh`. Requires `love-release`, `love.js`, `butler` (logged in), node and the macOS `iconutil`/`sips`/`plutil` tools.

See `CLAUDE.md` for the architecture and engine contracts, and `AGENTS.md` for the short version.

---
title: Assets
description: How fonts, images, sounds and cursors are preloaded through cacheManager, and how the marketing art in assets/generated is rendered by the game itself.
order: 7
---

Every asset the game draws or plays goes through `engine/cacheManager.lua`, keyed by a short string, and must be loaded before anything asks for it. The template does that in `scenes/Preload.lua`, which is registered first in `main.lua` so its `load()` runs before any other scene builds UI. Marketing images (icon, cover, banners) are not hand-drawn: they are LÖVE scenes under `scenes/assets/` rendered to PNG by `engine/AssetExporter.lua` when you run `love . --export-assets`.

## Preloading

`cacheManager` keeps separate tables for images, spritesheets, sounds, music and fonts. Each `preload*` call errors if the key is already taken, and each `get*` call errors if the key is missing, so a typo fails loudly instead of drawing nothing.

| Function | Loads | Notes |
|---|---|---|
| `preloadFont(key, path, size, hinting)` | `love.graphics.newFont` | A `nil` `path` loads LOVE's built-in default font. `hinting` is optional (`"normal"`, `"light"`, `"mono"`, `"none"`). `hasFont(key)` checks without erroring. |
| `preloadImage(key, path)` | `love.graphics.newImage` | Read back with `getImage(key)`. |
| `preloadSpritesheet(key, path, frameWidth, frameHeight, keys)` | image plus one quad per name in `keys` | `getSpritesheet(key)` returns `{ image, quads }`; frames are indexed left to right, top to bottom. |
| `preloadSound(key, path)` | `love.audio.newSource(path, "static")` | Short effects, fully decoded. |
| `preloadMusic(key, path)` | `love.audio.newSource(path, "stream")` | Long tracks, streamed. |

`scenes/Preload.lua` in the template loads the four UI fonts and the input prompt sheet:

```lua
function Preload:load()
  cacheManager.preloadFont("header", nil, 24)
  cacheManager.preloadFont("subheader", nil, 20)
  cacheManager.preloadFont("body", nil, 15)
  cacheManager.preloadFont("small", nil, 12)
  cacheManager.preloadImage(glyphs.IMAGE_KEY, glyphs.IMAGE_PATH)
end
```

Add your own spritesheets, sounds and music to the same function. `Preload` is never made current; it exists for this side effect (see `scenes.md`).

### Font keys

`engine/ui` looks fonts up by key, so these four names are a contract (see `engine.md#contracts`): `body` is the `UIText` default, `small` is used by `Button` and `UIBar`, and `header`/`subheader` are for your own titles. All four are LOVE's built-in default font, loaded by passing `nil` as the path. The marketing scenes use `assets/fonts/PixelOperator8.ttf` instead; Pixel Operator renders cleanly at multiples of 8, which is why they use sizes like 48, 64, 96 and 128.

The asset scenes add fonts lazily under `asset-<size>` keys. `gameObjects/Wordmark.lua` does this in `Wordmark.font(size)`: it checks `cacheManager.hasFont("asset-" .. size)` and calls `preloadFont` with `"mono"` hinting on first use, so glyph edges stay binary and transparent exports have no fringes.

### Prompt sheet

`engine/input/glyphs.lua` exports `IMAGE_KEY = "input-prompts"` and `IMAGE_PATH = "assets/graphics/input-prompts.png"`. `InputPrompt` needs that image in the cache; without it, prompts fall back to drawn text keycaps.

## Cursors

Cursors are declared in the `cursors` block of the `Game` config in `main.lua`. Each entry has an image `path` and a hotspot (`hotX`, `hotY`):

```lua
cursors = {
  default = { path = "assets/cursors/default.png", hotX = 8, hotY = 8 },
  active = { path = "assets/cursors/active.png", hotX = 8, hotY = 8 },
},
```

`engine/Game.lua` turns each entry into a `love.mouse.newCursor` and hands the table to `engine/cursorManager.lua`. If a `default` key exists it is applied at startup. `Button` switches to `active` on hover and back to `default` on exit, so both keys must exist. Use `cursorManager.setCursor(key)`, `removeCursor()` and `resetCursor()` yourself if you add more.

## Audio

`engine/audioManager.lua` plays sources that are already in the cache; it does not load files. Preload in `Preload`, then play by key:

```lua
-- scenes/Preload.lua
cacheManager.preloadSound("boom", "assets/sounds/boom.wav")
cacheManager.preloadMusic("theme", "assets/music/theme.ogg")

-- anywhere in game code
local audioManager = require "engine.audioManager"
audioManager.playSound("boom")        -- restarts the source, volume 0.5 by default
audioManager.playMusic("theme", true) -- stops the current track, loops, volume 0.2
audioManager.pauseMusic()
audioManager.resumeMusic()
audioManager.stopMusic()
audioManager.setMusicVolume(0.5)      -- clamped to 0..1, applies to the playing track
audioManager.setSoundVolume(0.8)      -- clamped to 0..1, applies to later playSound calls
```

Only one music track plays at a time. In dev, the hot reload callback calls `stopMusic()` before re-running `main.lua`. `assets/sounds/` and `assets/music/` exist as empty directories for your files.

## Marketing art

`assets/generated/*.png` are rendered from live scenes, so a palette or font change regenerates every image and shows up as an image diff in git. Never hand-edit those PNGs; change the scene and re-export.

### The `assets` block

`main.lua` lists the images in the `assets` block of the `Game` config:

```lua
assets = {
  outputDir = "assets/generated",
  items = {
    { name = "icon",    scene = AssetIcon,    width = 1024, height = 1024 },
    { name = "favicon", scene = AssetFavicon, width = 64,   height = 64 },
    { name = "cover",   scene = AssetCover,   width = 630,  height = 500 },
    { name = "social",  scene = AssetSocial,  width = 1200, height = 630 },
    { name = "wide",    scene = AssetWide,    width = 1920, height = 1080 },
    { name = "logo",    scene = AssetLogo,    width = 1600, height = 400,  transparent = true },
  },
},
```

| Field | Type | Meaning |
|---|---|---|
| `name` | string | Output file name without extension, written as `<outputDir>/<name>.png`. |
| `scene` | constructor or string | A Scene constructor called as `ctor(width, height)`, or the name of a scene already registered with `sceneManager`. |
| `width`, `height` | number | Exact output size in pixels. |
| `transparent` | boolean, optional | Clear to transparent instead of the scene's `backgroundColor`. |
| `postProcess` | boolean, optional | Run the `shaders` chain from the `Game` config over the result. |

`transparent` and `postProcess` are mutually exclusive: shaders force alpha to 1, and `AssetExporter.render` asserts if both are set. `outputDir` defaults to `assets/generated` and is relative to the project source directory.

| Image | Size | Used for |
|---|---|---|
| `icon.png` | 1024x1024 | Mac `.icns`, Windows `.exe` icon, store listings |
| `favicon.png` | 64x64 | Web build favicon |
| `cover.png` | 630x500 | itch.io cover image |
| `social.png` | 1200x630 | OpenGraph and social posts |
| `wide.png` | 1920x1080 | itch.io theme banner or background |
| `logo.png` | 1600x400, transparent | Press kit and banners |

### Asset scenes

Each file in `scenes/assets/` is an ordinary `Scene` whose constructor takes `(width, height)` and stores them, then in `load()` adds a `UICanvas` sized with `styles.width`/`styles.height` and composes text with `gameObjects/Wordmark.lua`:

```lua
function AssetCover:load()
  local padding = 24
  self:addGameObject(UICanvas("AssetCoverUI", {
    Wordmark("AssetCoverMark", {
      lines = { "NEW", "GAME" },
      subtitle = "Built with spooki-love",
      titleSize = 64,
      subtitleSize = 16,
      canvasHeight = self.height - padding * 2,
    }),
  }, { width = self.width, height = self.height, padding = Vector4(padding, padding, padding, padding) }))
end
```

`Wordmark` takes `lines` (title lines, top to bottom), an optional `subtitle`, `titleSize` and optional `subtitleSize` (default is `titleSize / 3` snapped down to a multiple of 8), `color`, `subtitleColor`, `gap` and `canvasHeight`, which centres the block vertically. Title colour defaults to `colors.vec4Yellow` and subtitle to `colors.vec4Grey` from `constants/colors.lua`. `Icon.lua` and `Favicon.lua` wrap the wordmark in a `UIBox` frame with a `colors.vec4Green` border.

To put your own game's name on the images, edit the `lines` and `subtitle` in each asset scene (and the Menu wordmark in `scenes/Menu.lua`). `init.sh` does this for you when scaffolding; the `{ "NEW", "GAME" }`, `"NEW GAME"` and `{ "N" }` literals are its anchors, so if you rename them in the template, update `init.sh` too.

### Exporting

```sh
/Applications/love.app/Contents/MacOS/love . --export-assets
```

`Game:load` checks `Game:hasArg("--export-assets")` after scenes and shaders are set up but before hot reload or the MCP bridge start. `AssetExporter.export` creates `outputDir`, then for each item constructs the scene, runs `load()`, `handleLoad()`, `start()` and one `handleUpdate(0)`, draws it to a canvas of the exact size, optionally runs the post-processing chain, encodes PNG and writes it with plain `io` so the file can land outside LÖVE's save directory. It prints `exported <path> (<w>x<h>)` per image and the game quits without drawing a frame. `scripts/release.sh` runs this as its first step and fails if any of the six files is missing.

## Credits

`ASSET_LIST.md` at the repo root tracks third-party assets and licences. It currently lists Pixel Operator by Jayvee Enaguas (CC0 / SIL OFL) for `assets/fonts/PixelOperator8.ttf`, the project cursors in `assets/cursors/`, and Kenney's Input Prompts Pixel 16x sheet (CC0) at `assets/graphics/input-prompts.png`. Add a line for every asset you bring in.

## Uploading to itch.io

`scripts/release.sh` bakes `icon.png` and `favicon.png` into the builds and pushes the builds with butler, but itch.io has no API for page images, so `cover.png`, `wide.png`, `social.png`, `logo.png` and screenshots are uploaded by hand. The script prints the list at the end of a run; see `build-and-release.md` for the checklist.

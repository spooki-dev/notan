# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Notan is a desktop image tool for painters, not a game: it opens a photo and applies a stack of GPU effects to it — blur, levels, saturation, posterise — so the values in a reference can be read as flat shapes before painting them. It is built on the spooki-love LÖVE (Love2D) 11.5 template, written in plain Lua (LuaJIT on desktop, PUC Lua 5.1 in the love.js web build). The reusable engine lives under `engine/` and must not require anything outside it; the app is configured from `main.lua`. Input is action-based (`engine/input/`): game code reads named actions, never keys or gamepad buttons directly, so every game gets remapping, gamepad support and on-screen prompts for free (see `docs/input.md`). No build step or package manager.

`docs/*.md` is published at https://spookidev.com/spooki-love/docs (the site pulls `main` at build time). Every page needs `title`, `description` and `order` frontmatter and no H1; file names are the URL slugs; link between pages as `scenes.md` and to source as repo-root paths like `engine/Scene.lua`. See `docs/README.md`.

## Running the App

```sh
# love is not on PATH on macOS:
/Applications/love.app/Contents/MacOS/love .
/Applications/love.app/Contents/MacOS/love . path/to/photo.jpg   # open straight onto an image
```

Keys: `O` open, `E` export a PNG next to the source, `TAB` hold to see the original, `0` fit, `1` 100%, `G` toggle the grid, `R` reset the effects, `H` hide the panel, `C` key bindings. Images can also be dragged onto the window. Arrow keys move through the panel and adjust the selected slider.

There is no test command. Verify changes by running the app. The one lint is `scripts/lint-lua51.sh` (see below). Hot-reload is active in dev mode — saved edits under the directories listed in the `watch` config in `main.lua` reload automatically. Backtick key force-reloads. Reload clears `package.loaded`, re-executes `main.lua` and re-runs `love.load()`, so **duplicate GameObject names will throw on reload**. `main.lua` sets `io.stdout:setvbuf("no")` so prints appear immediately when stdout is piped.

### Lua 5.1 compatibility (web build)

love.js runs the game on PUC Lua 5.1, not LuaJIT, so game and engine code must stay within the Lua 5.1 subset both runtimes share. No `goto`/`::label::`, no `ffi`/`jit`/`bit` outside `engine/dev`, no `table.pack`/`table.unpack`/`math.tointeger`, no `\z`/`\x` string escapes. Three layers enforce this:

- `.luarc.json` sets the LuaLS runtime to `Lua 5.1`, so the editor flags these as syntax errors.
- `scripts/lint-lua51.sh [files...]` parses files with a real `luac` 5.1 (`-p`, no execution). It builds Lua 5.1.5 from the official tarball into `~/.cache/love-release/` on first run because Homebrew no longer ships `lua@5.1`. With no arguments it checks every tracked `.lua` file.
- `.githooks/pre-commit` runs that lint over staged Lua files. Enable it per clone with `git config core.hooksPath .githooks`. `scripts/release.sh` also runs it over the contents of the built `.love` before packaging anything, and so does `.github/workflows/ci.yml`.

### Build and release

`scripts/release.sh` does the whole release: regenerates the marketing art, builds the `.love`, packages Mac and Windows from the official LÖVE 11.5 runtime with the generated icon baked in, builds the web version with a favicon, pushes every channel to itch.io with butler, then prints the page images that must be uploaded by hand and opens the itch edit page. Fill in `TITLE`, `PKG`, `UTI`, `AUTHOR` and `ITCH` at the top of the script first. `scripts/release.sh --no-push` does everything except the butler pushes.

```sh
scripts/release.sh            # full release
scripts/release.sh --no-push  # build only, artefacts in releases/<PKG>/
love . --export-assets        # just regenerate assets/generated/*.png and quit
```

Notes:
- The `.love` is a plain zip of the paths `scripts/love-filelist.sh` prints: `git ls-files` minus a list of **anchored** extended regexes. Keep them anchored. This replaced `love-release`, which matched its excludes as unanchored Lua patterns, so `-x engine/dev` also swallowed `engine/device/` and shipped a build that died on `module 'engine.device.backends' not found`.
- `scripts/check-requires.sh` is the regression test for that: it resolves every `require "a.b.c"` and every quoted asset path in the shipped Lua against the shipped file list, treating a `pcall(require, ...)` as optional. `scripts/release.sh` runs it over the unpacked `.love` and CI runs it over the file list, because the working tree never shows a module that packaging dropped.
- Mac/Windows packages are assembled by the script from `love-11.5-{macos,win32,win64}.zip`, cached in `~/.cache/love-release/`.
- The tracked `DEV` marker file turns on hot reload and the MCP bridge; builds exclude it so shipped copies run clean.
- Windows icons are patched into `love.exe` by `scripts/patch-win-icon.mjs` (node, deps in `scripts/package.json`). The Mac icon is an `.icns` built with `iconutil`; the script also removes `CFBundleIconName` so macOS reads the `.icns` rather than `Assets.car`.
- The web page is our own template in `scripts/web/` (`index.html` with a `{{TITLE}}` placeholder, `theme/love.css`), copied over the love.js output so the page shows only the canvas on black: no heading, footer or "Powered by" text. love.js's `game.js`/`love.js`/`love.wasm`/`game.data` are kept as generated. Change the colours in `theme/love.css` and the loading text in `index.html` to suit the game.
- butler can only push build channels. itch.io has no API for cover/screenshot images, so those remain a manual upload. The "This file will be played in the browser" flag must be ticked on the *web* channel upload on the edit page (once, after the first push); ticking it on the `.love` upload fails with "Failed to find index.html".
- butler comes from https://itch.io/docs/butler/ (the Homebrew `butler` cask is an unrelated app). Run `butler login` once in a real terminal.

### Marketing assets

`assets/generated/*.png` are rendered by the game itself from `scenes/assets/*.lua` via `engine/AssetExporter.lua`, so a colour or font change regenerates them (and shows up as an image diff in git). The `assets` block in `main.lua` lists each item with its exact pixel size, `postProcess = true` to run the post-processing shader chain (if any shaders are configured), or `transparent = true` for an alpha background (the two are mutually exclusive, shaders force alpha to 1). Asset scenes take `(width, height)` in their constructor, pass them to a `UICanvas` via `styles.width/height`, and compose text with `gameObjects/Wordmark.lua`, which lazily loads fonts under keys `asset-<size>` (sizes in multiples of 8 for PixelOperator8). Edit the `lines`/`subtitle` in each asset scene for your game.

`Icon.lua` and `Favicon.lua` carry no text: both are a full-bleed `gameObjects/NotanMark.lua`, a landscape in three flat values (light sky, mid peak, dark peak), defined as fractions of a square so the same code serves 1024px and 64px. An item may set its own `outputDir`; `app-icon` uses that to land in `assets/`, which ships inside the `.love`, because the dock and taskbar read the icon from the window (`icon` in the `Game` config) rather than from the `.app` or `.exe`.

### Debugging

`.vscode/launch.json` uses the `lua-local` debugger. Set `LOCAL_LUA_DEBUGGER_VSCODE=1` to have `main.lua` start `lldebugger`. `.luarc.json` configures LuaLS with the Lua 5.1 runtime (the web build's Lua, see above) and love2d types. In dev the engine also starts the lovepilot MCP bridge (`engine/dev/mcp_bridge.lua`) on port 12345; large screenshots can stall the bridge, so prefer `love.graphics.captureScreenshot("x.png")` into the save directory when the picture is noisy.

## Architecture

### Entry point

`main.lua` builds the game from a config table and is the only place scenes are registered:

```lua
Game({
  title = "Notan",
  env = "dev",                      -- enables hot reload and the MCP bridge
  scenes = { Preload, Viewer, Controls },
  defaultScene = "Viewer",
  cursors = { default = { path = "assets/cursors/default.png", hotX = 8, hotY = 8 }, active = { ... } },
  shaders = {},                     -- optional post-processing chain, in order
  watch = { "engine", "scenes", "gameObjects", "constants", "state", "effects", "app" },
  input = { deadzone = 0.25, actions = { { name = "open_image", label = "Open image", category = "File", bindings = { "key:o", "pad:y" } }, ... } },
  assets = { outputDir = "assets/generated", items = { { name = "icon", scene = AssetIcon, width = 1024, height = 1024 }, ... } },
})
```

`scenes` is registered in order and `sceneManager.addScene` calls each scene's `load()` immediately, so **`Preload` must be first** — other scenes build UI that needs its cached fonts. `defaultScene` is made current after registration. `cursors`, `shaders`, `watch` and `input` are optional; `inputMap.init(config.input)` runs before scenes load so prompts can read bindings.

### Core engine (`engine/`)

| File | Purpose |
|---|---|
| `Game.lua` | Top-level game class built from the config table; `love.load(args)` is forwarded so `Game:hasArg("--flag")` works. Owns sceneManager, audioManager, cursorManager, inputManager, postProcessing. Wires all `love.*` callbacks. |
| `Scene.lua` | Base scene class. Manages layers (ground/entities/ui), gameObject registry, camera, input dispatch. Objects in `ui` layer draw without camera transform. |
| `GameObject.lua` | Base class for all entities. Handles position, rendering (sprites/quads/shapes/text), animation, mouse/keyboard events, and children. |
| `sceneManager.lua` | Singleton. Stores scenes by name, delegates update/draw/input to the current scene. `setCurrentScene` errors if called with the already-current scene and calls the scene's `start()` on every activation. `addScene`/`resetScene` return the instance; `getScene(name)` looks one up. |
| `saveManager.lua` | Single-slot save file in the save directory, serialised as Lua source. `save`/`load`/`exists`/`delete` never throw; see **Saving** below. |
| `Camera.lua` | Camera with position, zoom, bounds-based culling. |
| `cacheManager.lua` | Preloads and caches spritesheets, images, fonts, sounds. Must be populated (see `scenes/Preload.lua`) before assets are used. |
| `audioManager.lua` | Centralised audio: load/play sounds and music. |
| `cursorManager.lua` | Named cursor registry populated from the `cursors` config. |
| `PostProcessing.lua` | Ping-pong canvas shader chain populated from the `shaders` config. `uniforms` is cleared every frame and refilled by the current scene's optional `updateShaderUniforms(uniforms, dt)` hook. `process(canvas, scene)` runs the chain offscreen at any size. |
| `AssetExporter.lua` | Renders asset scenes to canvases at exact sizes and writes PNGs with plain `io` (outside the save dir). Triggered by `love . --export-assets`, which quits before any dev tooling starts. |
| `renderer.lua` | Shared rendering utilities used by GameObject's `handleDraw`. |
| `input/inputMap.lua` | Action-based input singleton: actions with keyboard/mouse/gamepad bindings, per-frame polling with analog strength, `down/pressed/released/strength/axis/vector`, action events, active-device tracking, rebind capture, persistence to `bindings.lua`. Locked `ui_*` menu actions are built in. |
| `input/glyphs.lua` | Labels ("Space", "RT", "Cross") and sprite tiles for bindings, indexed into the Kenney Input Prompts Pixel 16× sheet (`assets/graphics/input-prompts.png`, preloaded under key `input-prompts`). Nintendo pads swap A/B and X/Y. |
| `State.lua` | Generic key/value state container (`state/GameState.lua` is an instance). Deep-copies its initial table so `reset()` really restores the defaults. |
| `ui/` | UI primitives: `UIBox`, `UICanvas`, `UIStack`, `UIText`, `UIBar`, `BarFill`, `Button` (focusable), `InputPrompt` (what an action is bound to on the active device), `FocusGroup` (keyboard/gamepad navigation over focusables). |
| `components/` | Optional mixins: `HitHurtBox`, `LightManager` (wraps the shadows lib). |
| `utils/` | Small helpers: easing, hexcolor, intersection, noise, perlin, theta pathfinding, `table.deepCopy`, table serialisation (Lua 5.1 safe, deterministic). |
| `lib/` | Vendored third-party code: `classic.lua` (rxi/classic), `hotReload.lua`, `shadows/` (Shädows light engine, unmaintained upstream; read its README before modifying). |
| `dev/mcp_bridge.lua` | lovepilot MCP bridge, loaded via `pcall` in dev only. Its virtual input feeds `inputMap` polling; `send_input` accepts `action_down`/`action_up` as well as keys and mouse. |

### Engine contracts the game must honour

- **Font keys**: `engine/ui` looks up fonts by key `body` (UIText default), `small` (Button, UIBar), plus `header`/`subheader`. Preload them in the first scene.
- **Cursor keys**: `Button` switches between `active` and `default`. Provide both in the `cursors` config.
- **Layer names**: `ground`, `entities`, `ui`. `ui` draws in screen space; UI objects default to it.
- **Input actions**: read input via `inputMap` (`require "engine.input.inputMap"`), never `love.keyboard`/`love.joystick` in game code. `ui_up/ui_down/ui_left/ui_right/ui_accept/ui_cancel` always exist and are locked. Binding shorthand: `key:<scancode>`, `mouse:<n>`, `pad:<button>`, `axis:<axis>+|-`.
- **Prompt sheet**: `InputPrompt` needs `cacheManager.preloadImage(glyphs.IMAGE_KEY, glyphs.IMAGE_PATH)` in `Preload`; without it prompts fall back to drawn text keycaps.
- **Save identity**: `conf.lua` sets `t.identity`, which names the save directory holding `bindings.lua` and `windowpos.txt`.
- **Quit hook**: `Game:quit` calls `onQuit()` on the current scene if defined. Autosave there.
- **Window hooks**: `Game` forwards `love.filedropped`/`love.directorydropped`/`love.resize` to the current scene as optional `filedropped(file)`, `directorydropped(path)` and `resize(w, h)` methods. A dropped file's `getFilename()` is its absolute path.

### Saving

`engine/saveManager.lua` keeps one save file in LÖVE's save directory as Lua source (via `engine/utils/table_serialize.lua`). API: `configure{ filename, version, migrate }`, `isAvailable()`, `exists()`, `save(data) -> ok, err`, `load() -> table|nil`, `delete()`. Every call is wrapped in `pcall`: a missing or read-only store makes `save` return false and `load` return nil, never an error. The engine never decides what to save; the game passes a plain-data table (numbers, strings, booleans, nested tables) and gets the same shape back. `save` stamps `version`; `load` rejects a different version unless a `migrate(data, fromVersion)` function is configured.

Hooks: `Game:quit` calls the current scene's optional `onQuit()`, which is where a game autosaves. `sceneManager.resetScene(name)` returns the fresh instance and `getScene(name)` looks one up, so a menu can rebuild a scene and hand it loaded data before `setCurrentScene` runs its `start()`. Set `t.identity` in `conf.lua` so source runs and fused builds share one save directory.

Web: love.js keeps the save directory in IndexedDB but only flushes it in its own `beforeunload` listener, and does not expose `FS` to the page, so `scripts/web/index.html` dispatches a synthetic `beforeunload` on `pagehide`, when the tab is hidden and every 10 s. Lua has no access to `localStorage`; when IndexedDB is unavailable the writes simply do not persist and the game carries on.

### OOP pattern

Uses vendored `engine/lib/classic.lua` (rxi/classic):
```lua
local Foo = Base:extend()
function Foo:new(...)
  Foo.super.new(self, ...)
end
```

### Scenes (`scenes/`)

- `Preload.lua` — preloads fonts via cacheManager. Never made current; registered first for its `load()` side effect.
- `Viewer.lua` — the app. Default scene: owns the Pipeline, the pan/zoom transform, image loading (drop, picker, command-line argument), PNG export and the saved settings.
- `Controls.lua` — rebinding screen: every unlocked action by category with a keyboard/mouse and a gamepad cell, press-to-rebind, stolen-binding notice, reset, back. Navigable with mouse, keyboard or pad. Add actions to `main.lua` and they appear here.
- `Menu.lua` and `Game.lua` are leftovers from the template, no longer registered in `main.lua`.

Scene names (passed to `Scene.super.new(self, "Name")`) must be unique. To add a scene, create it in `scenes/`, require it in `main.lua` and add it to the `scenes` array. See `docs/scenes.md`.

### GameObjects (`gameObjects/`)

All game objects extend `GameObject`. Key naming rule: **every GameObject name must be unique within a scene** — duplicates throw an error. `SampleGameObject.lua` and `SampleUIGameObject.lua` are starting points.

Auto-registered event handlers (define on a GameObject to opt in): `onClick`, `onMouseOver`, `onMouseEntered`, `onMouseExit`, `handleScroll`, `onKeyPressed`, `onActionPressed`/`onActionReleased` (named input actions; prefer these over raw keys), `getHitbox`/`getHurtbox`. Scenes may define `onActionPressed(name)`/`onActionReleased(name)` too.

### UI system (`engine/ui/`)

Hand-rolled flexbox-style layout via `UIBox`, `UICanvas`, `UIStack`, `UIText`, `UIBar`, `BarFill`, `Button`. Require as `require "engine.ui.UIBox"`.

Key quirks:
- `Vector4` ordering for `padding`/`border`/`margin` is **(top, right, bottom, left)** — not CSS order.
- Supported styles: `display` (`flex`/`block`/`none`), `flexDirection` ("row"), `gap`, `justifyContent` ("center"), `alignItems` ("center"), `position` ("absolute" with `left`/`top`/`right`/`bottom`), `width` (number or `"NN%"`), explicit `height`, `zIndex`, `hover.background`/`hover.borderColor`.
- Debug: pass `{ debugBox = true, debugPadding = true }` as 4th UIBox ctor arg.
- UI objects default to the `ui` layer (drawn without camera transform).
- `UIBar(name, ...)` names its children `name .. "Container"` and `name .. "BarContainer"`.

### App-side code

| Path | Purpose |
|---|---|
| `effects/init.lua` | The effect chain as data: one entry per GPU pass with its GLSL source, the parameters the panel exposes and a `send` that pushes them as uniforms. List order is processing order (blur → levels → saturation → posterise). Add an entry here and it appears in the panel, the saved settings and the reset action with no other change. An entry marked `overlay = true` carries parameters but no GLSL: the Pipeline skips it and `Viewer` draws it over the image instead (the grid, whose lines must stay a pixel wide at every zoom). |
| `effects/Pipeline.lua` | Owns the working-size copy of the image and two canvases, ping-pongs the enabled effects over them, and caches the result until `markDirty()`. Also holds every parameter value, so the panel and the renderer never disagree. |
| `app/grid.lua` | The composition grid: evenly spaced lines over a rectangle, drawn in screen space by `Viewer:draw` and at image scale by `Viewer:exportImageData` so the export matches the window. |
| `app/imageIO.lua` | Reading and writing images outside LÖVE's sandbox: paths are read with plain `io` and handed to `love.image` as FileData. Also builds the host OS file-picker command. |
| `app/dialogThread.lua` | Runs that picker command on a thread, because `io.popen` blocks until the dialog closes. Pushes the chosen path on a channel; `Viewer:update` polls for it. |
| `gameObjects/ControlPanel.lua` | The side panel. Drawn by hand rather than composed from `engine/ui`, which has no slider and no drag; rows are flattened so the mouse and the `ui_*` actions address the same thing. |

Images larger than 4096px on the long edge are scaled down once on load (`MAX_EDGE` in `effects/Pipeline.lua`): every pass costs width × height, and nothing about judging values needs more.

### Game-side code

- `constants/colors.lua` — palette (`black`, `dark`, `light`, `white`, `green`, `yellow`, `grey`) plus `vec4*` variants. UI code passes `Vector4(r,g,b,a)`. Menu and the asset scenes take their title colours from here.
- `state/GameState.lua` — game state singleton over `engine/State.lua`.

### Scene layers

Every scene has three default layers: `ground` (z=1), `entities` (z=2), `ui` (z=3). Non-UI layers are Y-sorted and camera-culled. Set `gameObject.layer` before adding to scene.

## Conventions

- **Classes/Objects**: `PascalCase`. **Methods/Functions/Variables**: `camelCase`. **Constants**: `UPPER_CASE`.
- All functions documented with LuaDoc (`@param` with type, `@return` with type).
- Requires use dot-separated module paths: `require "engine.Scene"`, `require "engine.ui.UIBox"`. No `.lua` extension.
- Nothing under `engine/` may require from `scenes/`, `gameObjects/`, `constants/` or `state/`. Inject game data through the `Game` config or scene hooks instead.
- Avoid creating tables/objects inside `update` or `draw` loops (GC pressure).
- Use `assert()` for internal logic checks; custom error logging for non-fatal issues.
- Preloaded font keys: `header`, `subheader`, `body`, `small` (LOVE's built-in default font: `preloadFont` with a `nil` path). Asset scenes add `asset-<size>` from PixelOperator8.ttf on demand.
- Window: 1280x720, resizable, min 1024x600.
- Input: declare actions in `main.lua`, read them with `inputMap`, show them with `InputPrompt`.

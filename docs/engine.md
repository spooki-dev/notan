---
title: Engine
description: The Game config table, what Game.lua wires up, a module-by-module reference for everything under engine/, and the contracts a game must honour.
order: 6
---

Everything reusable lives under `engine/`, and nothing in there may require from `scenes/`, `gameObjects/`, `constants/` or `state/`. The game feeds the engine from one place: the config table passed to `Game({...})` in `main.lua`. This page annotates that table, explains what `engine/Game.lua` does with it, lists every engine module, and documents the smaller managers (state, saving, post-processing, caching, audio, cursors, input, colours, vectors) that the other pages only mention. For scenes see `scenes.md`, for `GameObject` see `game-objects.md`, for the UI primitives see `ui.md`.

## The Game config

`main.lua` builds the game from a single table. The shipped file, abridged:

```lua
local Game = require "engine.Game"

Game({
  title = "New Game",
  env = "dev",
  scenes = { Preload, Menu, GameScene, Controls },
  defaultScene = "Menu",
  cursors = {
    default = { path = "assets/cursors/default.png", hotX = 8, hotY = 8 },
    active = { path = "assets/cursors/active.png", hotX = 8, hotY = 8 },
  },
  watch = { "engine", "scenes", "gameObjects", "constants", "state" },
  input = {
    deadzone = 0.25,
    actions = {
      { name = "action", label = "Action", category = "Actions", bindings = { "key:space", "mouse:1", "pad:a" } },
    },
  },
  assets = {
    outputDir = "assets/generated",
    items = {
      { name = "icon", scene = AssetIcon, width = 1024, height = 1024 },
      { name = "logo", scene = AssetLogo, width = 1600, height = 400, transparent = true },
    },
  },
})
```

| Field | Type | Required | Meaning |
|---|---|---|---|
| `title` | string | yes | Window title, applied with `love.window.setTitle` in `Game:load`. |
| `icon` | string | no | Window icon, a path inside the game source, applied with `love.window.setIcon` in `Game:load`. A missing file prints a line and keeps the LÖVE default. |
| `env` | string | no | `"dev"` turns on hot reload and the MCP bridge. Anything else runs clean. |
| `scenes` | array of Scene constructors | yes, non-empty | Registered in order with `sceneManager.addScene`, which instantiates each and runs its `load()` immediately. `Preload` must be first. |
| `defaultScene` | string | yes | Scene name made current after registration. |
| `cursors` | table of `{ path, hotX, hotY }` | no | Named cursors created with `love.mouse.newCursor`. `default` is applied at startup if present. `Button` needs `default` and `active`. |
| `shaders` | array of shader definitions | no | Post-processing chain, applied in order. See below. |
| `watch` | array of directories | no | Hot-reload watch list in dev. Defaults to `engine`, `scenes`, `gameObjects`, `constants`. |
| `input` | `{ actions, deadzone, saveFile }` | no | Named input actions and default bindings. `deadzone` defaults to 0.25; `saveFile` defaults to `"bindings.lua"`, `false` disables saving. See `input.md`. |
| `assets` | `{ outputDir, items }` | no | Marketing art rendered by `love . --export-assets`. Each item is `{ name, scene, width, height, transparent, postProcess }`. See `assets.md`. |

`Game:new` asserts on `title`, `scenes` and `defaultScene` and stores the rest with defaults. No other fields are read.

## What Game.lua does

`engine/Game.lua` is a `classic` class. Its constructor stores the config, grabs the singletons (`sceneManager`, `audioManager`, `cursorManager`, `inputMap` as `inputManager`) and a fresh `PostProcessing()`, then `initializeEvents` defines every `love.*` callback: `load`, `update`, `draw`, `mousepressed`, `mousereleased`, `mousemoved`, `wheelmoved`, `keypressed`, `keyreleased`, `gamepadpressed`, `gamepadreleased`, `gamepadaxis`, `joystickadded`, `joystickremoved`, `focus`, `resize` and `quit`.

`Game:load(args)` runs in this order:

1. Stores `args` so `Game:hasArg("--flag")` works, and (not on web) restores the window position saved in `windowpos.txt`.
2. Sets the window title and graphics defaults, including `setDefaultFilter("nearest", "nearest", 1)` for pixel art.
3. Builds cursors and calls `cursorManager.new(cursors)`, then `setCursor("default")` if defined.
4. `inputMap.init(config.input)`, before any scene loads, so prompts can read bindings. In dev, wires the MCP bridge's virtual keys and mouse into `inputMap`.
5. `sceneManager.addScene` for each constructor, then `setCurrentScene(defaultScene)`.
6. `postProcessing:load()` and `addShader` for each entry in `shaders`.
7. If `--export-assets` was passed, runs `AssetExporter.export` and quits before any dev tooling starts.
8. In dev, starts `hotReload` (stopping music on reload) over the `watch` directories and the MCP bridge on port 12345.

`Game:update(dt)` polls `inputMap.update(dt)` first, drains the pressed and released lists into `sceneManager.actionPressed`/`actionReleased`, updates post-processing time and the scene, clears `postProcessing.uniforms` and refills it from the current scene's optional `updateShaderUniforms(uniforms, dt)`, then ticks hot reload and the bridge. `Game:draw` wraps `sceneManager.draw()` in `beginCapture`/`endCapture`/`apply`. Raw mouse and key events go to `inputMap` first; a rebind capture in progress consumes them. Click dispatch happens on mouse release of button 1. `Game:focus(false)` calls `inputMap.releaseAll()`; `Game:quit` calls the current scene's optional `onQuit()` inside `pcall`, saves `windowpos.txt` and shuts the bridge down.

## Module reference

| Path | Purpose |
|---|---|
| `engine/Game.lua` | Top-level game class from the config table; owns the managers and wires every `love.*` callback. |
| `engine/Scene.lua` | Base scene: layers `ground` (1), `entities` (2), `ui` (3), object registry, camera, handler auto-registration, mouse/key/action dispatch. |
| `engine/GameObject.lua` | Base entity: position via `getPos`/`setPos`, size, rendering through `renderer`, animation, children, rigid-body movement, mouse hit-testing. |
| `engine/sceneManager.lua` | Singleton registry. `addScene(ctor)` instantiates and loads; `setCurrentScene(name)` errors if already current and calls `start()`; `getScene`, `getSceneConstructor`, `resetScene`, `getCurrentSceneObject`. |
| `engine/saveManager.lua` | Single-slot save file as Lua source. Never throws. See Saving. |
| `engine/State.lua` | Key/value state container with deep-copied defaults and `reset()`. |
| `engine/Camera.lua` | Position, zoom, rotation, `set`/`unset` transform, `getBounds` for culling, `followTarget`, `worldToScreen`, `getWorldMousePosition`. |
| `engine/cacheManager.lua` | Preload and fetch images, spritesheets, sounds, music and fonts by key. Errors on duplicates and misses. |
| `engine/audioManager.lua` | Play one music track and fire-and-forget sounds from the cache. |
| `engine/cursorManager.lua` | Named cursor registry filled from the `cursors` config. |
| `engine/PostProcessing.lua` | Ping-pong canvas shader chain with a shared per-frame `uniforms` table and offscreen `process`. |
| `engine/AssetExporter.lua` | Renders asset scenes to canvases at exact sizes and writes PNGs with plain `io`. |
| `engine/renderer.lua` | `renderer.draw(gameObject)`: fills, borders, text, images and quads, repeats, flips, debug overlays. |
| `engine/AnimationManager.lua` | Named frame lists over a cached spritesheet with frame rate, per-frame callbacks and play/pause/stop. |
| `engine/Vector2.lua` | Immutable-style 2D vector: `add`, `subtract`, `multiply`, `divide`, `scale`, `normalize`, `magnitude`, `dot`, `distance`. |
| `engine/Vector4.lua` | Four components `x y z w` with `unpack()` and `clone()`. Used for colours and box sides. |
| `engine/input/inputMap.lua` | Action-based input: bindings, polling, edges, strength, axes, rebinding, persistence, device tracking, virtual input. |
| `engine/input/glyphs.lua` | Labels and sprite tiles for bindings from the Kenney Input Prompts sheet (`IMAGE_KEY = "input-prompts"`). |
| `engine/ui/UIBox.lua` | Flexbox-style layout box. `UICanvas`, `UIStack`, `UIText`, `Button`, `UIBar`, `BarFill`, `InputPrompt` extend it or sit beside it; `FocusGroup` navigates focusables. See `ui.md`. |
| `engine/components/HitHurtBox.lua` | Mixin: `setHitbox`/`setHurtbox`, `getHitbox`/`getHurtbox`, `intersectsWith`, `checkCollisionsWith`, debug draw. |
| `engine/components/LightManager.lua` | Wraps the shadows library as a per-scene light world drawn after the world layers. |
| `engine/utils/array.lua` | `array_includes(arr, value)`. |
| `engine/utils/easing.lua` | `linear`, `inCubic`, `outCubic`, `inOutCubic` over 0..1. |
| `engine/utils/hexcolor.lua` | `hexToIntegerColor`, `hexToDecimalColor`, `hexToVec4Color`. |
| `engine/utils/id.lua` | `create_random_id()`: eight random lowercase letters. |
| `engine/utils/intersection.lua` | `rectangleIntersection(rect1, rect2)`. |
| `engine/utils/noise.lua` | Pure-maths sample generators for procedural audio: white noise, filters, waveforms, envelope. |
| `engine/utils/perlin.lua` | `Perlin.noise(x, y)`. |
| `engine/utils/system.lua` | `isWeb()`: true under love.js. |
| `engine/utils/table.lua` | `getTableSize(t)`, `deepCopy(t)`. |
| `engine/utils/table_serialize.lua` | `serialize(tbl)` to deterministic Lua source and `deserialize(str)` with an empty environment. Lua 5.1 safe. |
| `engine/utils/theta.lua` | Theta* grid pathfinding: `lineOfSight`, `findPath(grid, start, goal)`. |
| `engine/lib/classic.lua` | rxi/classic OOP: `Base:extend()`, `Foo.super.new(self, ...)`, `obj:is(Class)`. |
| `engine/lib/hotReload.lua` | Watches `.lua` files, clears `package.loaded`, re-executes `main.lua` and `love.load()`. Backtick key forces a reload. |
| `engine/lib/shadows/` | Vendored Shädows light engine, unmaintained upstream, require paths rewritten. Only `LightManager` uses it. Read its README before editing. |
| `engine/dev/mcp_bridge.lua` | lovepilot MCP bridge over TCP, dev only. See `development.md`. |

## Contracts the game must honour

- **Preload first.** `sceneManager.addScene` runs `load()` as soon as a scene is registered, so the first entry in `scenes` must cache fonts and images every other scene needs. `scenes/Preload.lua` does this and is never made current.
- **Font keys.** `engine/ui` looks up `body` (UIText default) and `small` (Button, UIBar, InputPrompt); `header` and `subheader` are preloaded for game scenes. `cacheManager.getFont` errors on a missing key.
- **Cursor keys.** `Button` switches between `active` and `default`; `cursorManager.setCursor` errors on an unknown key, so provide both in `cursors`.
- **Layer names.** `ground`, `entities`, `ui`. Set `gameObject.layer` before adding it; an unknown layer errors. `ui` draws in screen space after the camera is unset.
- **Name uniqueness.** Scene names (`Scene.super.new(self, "Name")`) are keys in `sceneManager`; GameObject names are keys per scene and duplicates throw, including on hot reload.
- **Input through actions.** Read `inputMap`, not `love.keyboard` or `love.joystick`, in game code. `ui_up`, `ui_down`, `ui_left`, `ui_right`, `ui_accept`, `ui_cancel` always exist and are locked.
- **Prompt sheet.** `InputPrompt` needs `cacheManager.preloadImage(glyphs.IMAGE_KEY, glyphs.IMAGE_PATH)` in Preload, otherwise prompts fall back to drawn keycaps.
- **Engine never requires game code.** Inject game data through the config or scene hooks. Game code may require anything under `engine/`.
- **Save identity.** `conf.lua` sets `t.identity = "newgame"`, which names the save directory used by `saveManager`, `bindings.lua` and `windowpos.txt`.

## State and GameState

`engine/State.lua` is a tiny container. `State:new(initialState)` deep-copies the table it is given, so `set` never mutates the defaults and `reset()` really restores them.

```lua
local State = require "engine.State"
local s = State({ score = 0, lives = 3 })
s:set("score", s:get("score") + 10)
s:reset()  -- score back to 0
```

`state/GameState.lua` is the game-side singleton, an instance created with `State({ timer = 0 })`. Add the fields your game needs to that table and read and write them with `GameState:get(key)` and `GameState:set(key, value)`. It is a plain instance, so `require "state.GameState"` returns the same object everywhere.

## Saving

`engine/saveManager.lua` keeps one save file in LÖVE's save directory as Lua source produced by `engine/utils/table_serialize.lua`. The engine never decides what to save: you hand `save` a plain-data table (numbers, strings, booleans, nested tables) and `load` gives the same shape back.

| Function | Returns | Behaviour |
|---|---|---|
| `configure(opts)` | nothing | Any subset of `filename` (default `"save.lua"`), `version` (default 1), `migrate` (function). Asserts on wrong types. Call once before saving or loading. |
| `isAvailable()` | boolean | Whether `love.filesystem.getSaveDirectory()` resolved. Cached after the first call; logs a warning when false. |
| `getPath()` | string or nil | Absolute path of the save file, for logging. |
| `exists()` | boolean | Whether the file exists. Does not validate it. |
| `save(data)` | `ok, err` | Stamps `data.version = config.version` (the table you pass is modified), serialises and writes. Returns `false, reason` for a non-table, an unavailable store, a serialisation failure or a write failure. |
| `load()` | table or nil | Nil when absent, unreadable, corrupt or on a version mismatch with no migration. A corrupt file is left in place so the next `save` replaces it. |
| `delete()` | boolean | True when the file is gone, including when it never existed. False when the store is unavailable. |

Versioning: `save` writes `version`. On `load`, a different version is handed to `migrate(data, fromVersion)` if one is configured; the result must be a table and is re-stamped with the current version, otherwise `load` returns nil. Every filesystem call is wrapped in `pcall`, warnings are printed with a `[saveManager]` prefix, and nothing throws.

```lua
local saveManager = require "engine.saveManager"
saveManager.configure({
  filename = "save.lua",
  version = 2,
  migrate = function(data, fromVersion)
    if fromVersion == 1 then data.lives = data.lives or 3 end
    return data
  end,
})

function GameScene:onQuit()        -- called by Game:quit
  saveManager.save({ level = self.level, lives = self.lives })
end

local data = saveManager.load()    -- nil on a fresh install
```

To hand loaded data to a fresh scene, `sceneManager.resetScene(name)` returns the new instance before `setCurrentScene` runs its `start()`. On the web build the save directory lives in IndexedDB and is flushed by the page template; see `build-and-release.md`.

## Post-processing

`engine/PostProcessing.lua` captures the whole frame into a canvas and runs an ordered chain of shaders over a canvas pair. Each entry in the `shaders` config is a table:

```lua
{
  name = "crt",
  shader = love.graphics.newShader("shaders/crt.glsl"),
  enabled = true,   -- optional, only `false` disables
  sendUniforms = function(shader, time, w, h, uniforms)
    shader:send("time", time)
    if uniforms.flash then shader:send("flash", uniforms.flash) end
  end,
}
```

`beginCapture`, `endCapture` and `apply` are called by `Game:draw`; with no shaders the captured canvas is drawn straight back. `addShader(def)` and `removeShader(name)` edit the chain at runtime, `enabled` toggles the whole thing, `resize(w, h)` is wired to `love.resize`, and `process(canvas, scene)` runs the chain over any canvas at any size (used by `AssetExporter` for `postProcess = true` items).

`postProcessing.uniforms` is one shared table. `Game:update` clears every key each frame and then calls the current scene's `updateShaderUniforms(uniforms, dt)` if it defines one, so switching scenes never leaves stale values behind. Fill it with whatever your `sendUniforms` functions read. No shaders ship with the template.

## Caches, audio and cursors

`engine/cacheManager.lua` stores assets under string keys and errors both on a duplicate preload and on a missing key:

| Preload | Get |
|---|---|
| `preloadImage(key, path)` | `getImage(key)` |
| `preloadSpritesheet(key, path, frameWidth, frameHeight, keys)` | `getSpritesheet(key)` returns `{ image, quads }`; `getSpritePosition(sourceW, frameW, frameH, index)` |
| `preloadSound(key, path)` (static) | `getSound(key)` |
| `preloadMusic(key, path)` (stream) | `getMusic(key)` |
| `preloadFont(key, path, size, hinting)` | `getFont(key)`, `hasFont(key)` |

`engine/audioManager.lua` plays from that cache: `playMusic(key, loop)` stops the current track and starts the new one at volume 0.2 (as written, music always loops), `pauseMusic()`, `resumeMusic()`, `stopMusic()`, `setMusicVolume(volume)` on the playing track, `setSoundVolume(volume)` (default 0.5) and `playSound(key)`, which restarts the source. Hot reload calls `stopMusic()`.

`engine/cursorManager.lua`: `new(cursorConfig)` takes the table of `love.Cursor` objects `Game:load` built, `setCursor(key)` applies one and errors on an unknown key, `getCurrentCursor()`, `removeCursor()` clears to the system cursor, `resetCursor()` re-applies the current key (called on window focus). `sceneManager.setCurrentScene` also resets the cursor with `love.mouse.setCursor()`.

## Input

`engine/input/inputMap.lua` is the single input singleton; `Game` exposes it as `game.inputManager`. The functions game code uses most:

| Function | Meaning |
|---|---|
| `down(name)`, `pressed(name)`, `released(name)` | Held, went down this frame, went up this frame. Unknown names error. |
| `strength(name)` | Analog 0..1 after the deadzone; keys and buttons read 1. |
| `axis(negative, positive)` | Signed -1..1 from two actions. |
| `vector(left, right, up, down)` | Two numbers, radial deadzone, clamped to length 1. No allocation. |
| `getActiveDevice()`, `getGamepadStyle()`, `onDeviceChanged(fn)` | `"keyboard"` or `"gamepad"`; `"xbox"`, `"playstation"`, `"nintendo"` or `"generic"`. |
| `bind`, `rebind`, `unbind`, `resetToDefaults`, `isDefault`, `getBindings` | Edit bindings; changes persist to `bindings.lua` in the save directory. |
| `startCapture(callback, opts)`, `cancelCapture()`, `isCapturing()` | Press-to-rebind capture; raw events are consumed while active. |
| `pressVirtualAction(name, duration)`, `releaseVirtualAction(name)` | Hold an action with no device (used by the MCP bridge). |

Scenes and objects also receive `onActionPressed(name)`/`onActionReleased(name)` events from `Game:update`. Binding shorthand is `key:<scancode>`, `mouse:<n>`, `pad:<button>`, `axis:<axis>+|-`. Full detail is in `input.md`.

## Colours

`constants/colors.lua` is game-side but every engine colour parameter expects one of its two shapes. It defines seven hex values (`green '#72751b'`, `black '#000000'`, `dark '#565a75'`, `light '#c6b7be'`, `white '#fafbf6'`, `yellow '#ffff00'`, `grey '#b3b3b3'`) and exports each twice through `engine/utils/hexcolor.lua`:

| Export | Shape | Use for |
|---|---|---|
| `black`, `dark`, `light`, `white`, `green`, `yellow`, `grey` | `{ r, g, b }` with 0..1 components | `scene.backgroundColor`, `love.graphics.setColor(unpack(c))` |
| `vec4Black`, `vec4Dark`, `vec4Light`, `vec4White`, `vec4Green`, `vec4Yellow`, `vec4Grey` | `Vector4(r, g, b, 1)` | UI styles: `background`, `borderColor`, `color`, `hover.*` |

Add a colour by adding a hex string and both conversions; `hexcolor.hexToVec4Color("#abc")` also accepts three-digit shorthand.

## Vectors and Camera

`Vector2(x, y)` operations return new vectors: `add`, `subtract`, `multiply`, `divide` (component-wise), `scale(scalar)`, `normalize`, `magnitude`, `dot`, `distance`. `GameObject:getPos()` returns a `Vector2` and `setPos(Vector2)` returns false if a rigid body would collide. `Vector4(x, y, z, w)` defaults missing components to 0 and offers `unpack()` and `clone()`; it doubles as an RGBA colour and as box sides in the order (top, right, bottom, left), see `ui.md`.

`Camera.new(x, y, zoom)` is a plain metatable class, one per scene at `scene.camera`. `set()` pushes rotate, scale and translate; `unset()` pops. `getBounds()` is the window rectangle offset by the camera position and is what `Scene:handleDraw` culls against. `followTarget(target, width, height)` centres on a GameObject and clamps to a map size when given. `getWorldMousePosition()` converts the mouse through zoom and position; `worldToScreen(x, y)` goes the other way.

## Vendored libraries and dev tooling

`engine/lib/classic.lua` (rxi/classic) is the OOP base for everything. `engine/lib/hotReload.lua` records `modtime` for every `.lua` under the watched directories, and on a change clears `package.loaded` (keeping the MCP bridge and a few `love.*` modules), re-executes `main.lua` and calls `love.load()`; the backtick key forces this. `engine/lib/shadows/` is the Shädows light engine with its requires rewritten to `engine.lib.shadows.*`; it is unmaintained upstream, so read its README before changing it.

`engine/dev/mcp_bridge.lua` is loaded with `pcall` and only started when `env == "dev"`. It listens on TCP port 12345 and answers `get_objects`, `run_lua`, `get_screenshot`, `send_input` (keys, mouse, and `action_down`/`action_up` for named actions), `watch_game_state`, `reload_code` and `list_lua_files`. Set `env` to anything other than `"dev"` for a shipped build so neither it nor hot reload starts. How to drive it from an editor is covered in `development.md`.

# AGENTS.md

Notan: a desktop image tool for painters (open a photo, stack GPU effects over it — blur, levels, saturation, posterise — to read its values as flat shapes), built on the spooki-love LÖVE (Love2D) 11.5 template in plain Lua. Desktop runs LuaJIT but the love.js web build runs PUC Lua 5.1, so code must stay within the shared 5.1 subset: no `goto`/`::label::`, no `ffi`/`jit`/`bit`, no `table.unpack`. `scripts/lint-lua51.sh` checks this with a real Lua 5.1 parser; the pre-commit hook in `.githooks/` and `scripts/release.sh` both run it. No package manager.

## Run / verify

```sh
/Applications/love.app/Contents/MacOS/love .   # `love` is not on PATH
```

There is no lint or test command. Verify by running the app (`love . path/to/photo.jpg` opens straight onto an image); saved edits under the directories listed in the `watch` config in `main.lua` hot-reload on save (backtick key force-reloads). Reload clears `package.loaded`, re-executes `main.lua` and re-runs `love.load()`, so any duplicate GameObject name will throw on reload.

## Structure & conventions

- `engine/` is the reusable engine and must not require anything outside itself. App code (`scenes/`, `gameObjects/`, `effects/`, `app/`, `constants/`, `state/`) is wired in from `main.lua`.
- The app itself: `scenes/Viewer.lua` (view transform, loading, export), `effects/init.lua` (the chain as data — add an entry and it appears in the panel), `effects/Pipeline.lua` (canvas ping-pong + parameter state), `gameObjects/ControlPanel.lua` (sliders), `app/imageIO.lua` + `app/dialogThread.lua` (files outside LÖVE's sandbox).
- Requires use dotted module paths: `require "engine.Scene"`, `require "engine.ui.UIBox"`, `require "engine.lib.classic"`. Files never need `.lua`.
- OOP = vendored `engine/lib/classic.lua` (rxi/classic). Pattern: `local Foo = Base.extend(Base)` and call `Foo.super.new(self, ...)` in the constructor.
- Scenes live in `scenes/` and are registered from `main.lua` via the `scenes` array in the `Game` config (`Preload` first, because `addScene` runs `load()` immediately). `defaultScene` picks the starting scene. Scene `name` must be unique and `setCurrentScene` errors if called with the current scene.
- GameObject handlers auto-register for dispatch: define `onClick`, `onMouseOver/onMouseEntered/onMouseExit`, `handleScroll`, `onKeyPressed`, `onActionPressed/onActionReleased`, `getHitbox/getHurtbox`. Names must be unique per scene.
- Input is action-based: actions are declared in the `input` block of `main.lua` and read with `require "engine.input.inputMap"` (`down/pressed/released/strength/axis/vector`), never `love.keyboard`/`love.joystick` in game code. Locked `ui_*` actions drive menus via `engine/ui/FocusGroup.lua`; `engine/ui/InputPrompt.lua` shows bindings as Kenney glyphs; `scenes/Controls.lua` rebinds and persists to `bindings.lua`. See `docs/input.md`.
- A scene may define `updateShaderUniforms(uniforms, dt)`; the engine clears `postProcessing.uniforms` every frame and calls it. Shaders passed in the `shaders` config read from it (none ship with the template).
- Saves go through `engine/saveManager` (single slot, Lua-source file in the save dir, never throws; `version` + optional `migrate`). The engine only stores the table it is given. `Game:quit` calls the current scene's optional `onQuit()`; `sceneManager.resetScene`/`addScene` return the instance and `getScene(name)` looks one up. Keep `t.identity` set in `conf.lua`.
- Assets/fonts must be preloaded through `engine/cacheManager` (see `scenes/Preload.lua`) before use. Font keys `header`, `subheader`, `body`, `small` and cursor keys `default`, `active` are contracts relied on by `engine/ui`.
- Marketing art in `assets/generated/` is rendered by `love . --export-assets` from `scenes/assets/*.lua` (engine side: `engine/AssetExporter.lua`); `scripts/release.sh` runs that, builds every platform and pushes to itch with butler. Do not hand-edit the generated PNGs.
- `constants/colors.lua` exports decimal `{r,g,b}` tables (`black`, `dark`, `light`, `white`, `green`) plus `vec4*` variants; UI code passes `Vector4(r,g,b,a)`.

## UI system (engine/ui: UIBox, UICanvas, UIStack, UIText, UIBar, BarFill, Button)

Hand-rolled flexbox-ish layout driven by `styles` tables. Quirks to know:

- `Vector4` ordering for `padding`/`border`/`margin` is **(top, right, bottom, left)** — not CSS order.
- Supported styles: `display` (`flex`/`block`/`none`), `flexDirection` ("row"), `gap`, `justifyContent` ("center"), `alignItems` ("center"), `position` ("absolute" with `left`/`top`/`right`/`bottom`), `width` as number or `"NN%"`, explicit `height`, `zIndex`, `hover.background`/`hover.borderColor`.
- 4th ctor arg of UIBox is a debug table: `{ debugBox = true, debugPadding = true }` etc.
- Layout is computed in `UIBox:load`/`recalculateHeight`/`recalculateChildPos`; it depends on parent widths, so stacking more than a flex row needs care. Default layer for UI objects is `ui` (drawn without camera transform).

## Third-party

- `engine/lib/shadows/` is the external "Shädows" light engine (unmaintained upstream; require paths rewritten for vendoring; read its README before touching). Only `engine/components/LightManager.lua` uses it.
- `engine/lib/classic.lua` is rxi/classic. `engine/dev/mcp_bridge.lua` is the lovepilot MCP bridge (dev only).
- `ASSET_LIST.md` tracks third-party asset credits.

## Debugging

`.vscode/launch.json` uses the `lua-local` debugger; set `LOCAL_LUA_DEBUGGER_VSCODE=1` to have `main.lua` start `lldebugger`. `.luarc.json` configures LuaLS (Lua 5.1 runtime so web-incompatible syntax is flagged, love2d types).

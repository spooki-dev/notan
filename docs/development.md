---
title: Development
description: The day-to-day loop of running the game, hot reloading, debugging with the MCP bridge and VSCode, and the conventions the code follows.
order: 10
---

There is no build step and no package manager. `scripts/test.sh` runs the examples regression suite (see `examples.md`); visual changes you still verify by running the game and looking at it. Dev mode (`env = "dev"` in `main.lua`) adds hot reload on save and a TCP bridge that lets external tooling inspect and drive the running game. This page covers that loop, the editor setup and the conventions that keep the code base consistent.

## Running the game

```sh
# love is not on PATH on macOS:
/Applications/love.app/Contents/MacOS/love .
```

`scripts/lint-lua51.sh` checks Lua 5.1 syntax for the web build (see `build-and-release.md`) and `scripts/test.sh` runs it before the examples suite. `love . --examples` opens the examples picker. `main.lua` calls `io.stdout:setvbuf("no")` before anything else, so `print` output appears immediately when stdout is piped to a file or another process.

### Window

`conf.lua` sets the window: title `"New Game"`, 1280x720, resizable with a 1024x600 minimum, `vsync = 1`, `msaa = 0`. It also sets `t.identity = "newgame"`, which names the save directory holding `bindings.lua`, `windowpos.txt` and any saves. `engine/Game.lua` restores the saved window position on desktop at startup and writes it back on quit.

## Hot reload

`engine/lib/hotReload.lua` is started by `Game:load` when `env == "dev"`. It watches `main.lua` plus every `.lua` file under the directories in the `watch` config:

```lua
watch = { "engine", "scenes", "gameObjects", "constants", "state" },
```

If `watch` is omitted the engine defaults to `engine`, `scenes`, `gameObjects` and `constants`. Each frame it compares file modtimes; when one changes it reloads. Press the backtick key to force a reload at any time.

A reload does the following:

1. Calls the engine's callback, which stops any playing music.
2. Clears `package.loaded` for every module except the MCP bridge and a few `love.*` entries, so the next `require` re-reads the file.
3. Re-executes `main.lua`, which builds a fresh `Game`.
4. Calls `love.load()` again, which re-registers every scene and runs their `load()`.

Because every scene's `load()` runs again, **duplicate GameObject names throw on reload** even if they would have gone unnoticed in a single run (see `game-objects.md`). State held in module-level locals is lost on reload; state in `state/GameState.lua` is rebuilt from its initial table.

`env` is the only switch. Set it to anything other than `"dev"` and hot reload and the MCP bridge do not start. The release script also excludes `engine/dev/` from the `.love`.

## MCP bridge

`engine/dev/mcp_bridge.lua` is the lovepilot MCP bridge, a non-blocking TCP server on port 12345 that lets an MCP client list game objects, take screenshots, subscribe to state changes and send virtual input. `engine/Game.lua` requires it through `pcall(require, "engine.dev.mcp_bridge")`, so a build without `engine/dev/` runs with it set to `nil`, and only calls `mcp_bridge.init(12345)` when `env == "dev"`.

The module is kept in `package.loaded` across hot reloads so its open socket and connected clients survive; `init` is safe to call again and skips rebinding an open port. `Game:load` re-registers the object getter after each reload. Its virtual input feeds `inputMap` polling, so `send_input` can press named actions (`action_down`/`action_up`) as well as keys and mouse buttons.

Screenshots are captured through `love.graphics.captureScreenshot` at the end of the frame and sent base64 encoded. Large screenshots can stall the bridge, so when the picture is busy prefer writing to disk yourself:

```lua
love.graphics.captureScreenshot("x.png") -- lands in the save directory
```

## Debugging in VSCode

`.vscode/launch.json` defines a `Debug Love` configuration of type `lua-local` that launches `/Applications/love.app/Contents/MacOS/love` with the arguments `.` and `debug`, using the repo root as the script root. `main.lua` starts the debugger only when the environment variable is set:

```lua
if os.getenv("LOCAL_LUA_DEBUGGER_VSCODE") == "1" then
  local lldebugger = require "lldebugger"
  lldebugger.start()
end
```

Set `LOCAL_LUA_DEBUGGER_VSCODE=1` in the debug environment to have `main.lua` start `lldebugger`; normal runs from the terminal leave it unset and are unaffected.

### LuaLS

`.luarc.json` configures the Lua language server: `Lua.runtime.version` is `Lua 5.1` so web-incompatible syntax is flagged as an error, `Lua.workspace.library` includes `${3rd}/love2d/library` for LÖVE types, and `love`, `array_includes` and `Vector4` are declared as globals (`.vscode/settings.json` repeats the globals list). Keep LuaDoc annotations on functions and classes (`---@class`, `---@param`, `---@return`) so the server can check call sites.

## Conventions

The full list lives in `CONVENTIONS.md` and the Conventions section of `CLAUDE.md`. The ones that matter most:

| Rule | Detail |
|---|---|
| Naming | Classes and objects `PascalCase`; methods, functions and variables `camelCase`; constants `UPPER_CASE_WITH_UNDERSCORES`. |
| Documentation | Every function has LuaDoc. Each `@param` includes a type and a short description; each `@return` includes a type. |
| Requires | Dotted module paths without `.lua`: `require "engine.Scene"`, `require "engine.ui.UIBox"`. |
| Engine isolation | Nothing under `engine/` may require from `scenes/`, `gameObjects/`, `constants/` or `state/`. Game data reaches the engine through the `Game` config in `main.lua` or a scene hook such as `updateShaderUniforms`. |
| Errors | `assert()` for internal invariants that should never fail; logging (for example `print`) for non-fatal issues the game can recover from. |
| Performance | Do not create tables or objects inside `update` or `draw`. Pre-allocate or pool anything created often. |
| OOP | Vendored `engine/lib/classic.lua`: `local Foo = Base:extend()` and `Foo.super.new(self, ...)` in the constructor. |
| Uniqueness | Scene names and GameObject names within a scene must be unique; both throw otherwise. |

```lua
--- Gets the width of the object.
--- @param newWidth number? The width to set (optional).
--- @return number The current width.
function GameObject:getWidth(newWidth)
```

### Where things go

- `engine/` is the reusable engine; do not edit it to add game behaviour.
- `scenes/` holds scenes, registered from the `scenes` array in `main.lua` with `Preload` first (see `scenes.md`).
- `gameObjects/` holds entities; `constants/` holds data such as `colors.lua`; `state/GameState.lua` is the shared state singleton.
- `engine/lib/` is vendored third-party code and `engine/dev/` is dev-only tooling, both left as they are.
- `ASSET_LIST.md` records third-party asset credits (see `assets.md`).

### Changelog

The repo keeps `CHANGELOG.md` at the root with one dated `##` section per batch of changes, each a short bullet list naming the files or modules touched. `init.sh` writes a fresh one for a scaffolded game. Add an entry when you land something a user of the template would want to know about.

## Scaffolding a new game

`init.sh` copies the template into a new directory and runs a wizard for the title, author and itch.io username, rewriting the window title, wordmarks, release variables, `README.md` and `CHANGELOG.md`. See `getting-started.md` for the walkthrough.

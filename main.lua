local Game = require "engine.Game"
local system = require "engine.utils.system"

local Preload = require "scenes.Preload"
local Viewer = require "scenes.Viewer"
local Controls = require "scenes.Controls"

-- Marketing asset scenes, rendered by `love . --export-assets` (never registered as app scenes).
local AssetIcon = require "scenes.assets.Icon"
local AssetFavicon = require "scenes.assets.Favicon"
local AssetCover = require "scenes.assets.Cover"
local AssetSocial = require "scenes.assets.Social"
local AssetWide = require "scenes.assets.Wide"
local AssetLogo = require "scenes.assets.Logo"

-- Flush prints immediately so logs are readable when stdout is piped.
io.stdout:setvbuf("no")

if os.getenv("LOCAL_LUA_DEBUGGER_VSCODE") == "1" then
  local lldebugger = require "lldebugger"
  lldebugger.start()
end

Game({
  title = "Notan",
  -- Hot reload and the MCP bridge are dev-only, and both are pointless in a
  -- browser: the source is a zip that cannot change and there is no socket.
  env = system.isWeb() and "prod" or "dev",
  -- Registered in order; Preload must come first because addScene runs load() immediately.
  scenes = { Preload, Viewer, Controls },
  defaultScene = "Viewer",
  cursors = {
    default = { path = "assets/cursors/default.png", hotX = 8, hotY = 8 },
    active = { path = "assets/cursors/active.png", hotX = 8, hotY = 8 },
  },
  watch = { "engine", "scenes", "gameObjects", "constants", "state", "effects", "app" },
  -- The device file picker (engine/device/filePicker.lua) is how an image gets
  -- in on every platform. Bytes rather than a decoded Image, because the
  -- Pipeline wants ImageData so it can read the dimensions and downscale
  -- before making a texture. 64 MiB because a photo straight off a camera can
  -- be far larger than the 16 MiB default.
  device = {
    filePicker = {
      deliver = "bytes",
      accept = { "image/*" },
      maxBytes = 64 * 1024 * 1024,
    },
  },
  -- Named input actions (see docs/input.md). Each binding is one input:
  -- "key:<scancode>", "mouse:<button>", "pad:<button>", "axis:<axis>+|-".
  -- The engine adds the locked ui_* actions itself, which drive the control
  -- panel; everything below is remappable from the Controls screen.
  input = {
    deadzone = 0.25,
    actions = {
      { name = "open_image",      label = "Open image",     category = "File",    bindings = { "key:o", "pad:y" } },
      { name = "export_image",    label = "Export PNG",     category = "File",    bindings = { "key:e" } },
      { name = "toggle_original", label = "Show original",  category = "View",    bindings = { "key:tab", "pad:x" } },
      { name = "fit_view",        label = "Fit to window",  category = "View",    bindings = { "key:0", "pad:leftstick" } },
      { name = "actual_size",     label = "Actual size",    category = "View",    bindings = { "key:1" } },
      { name = "toggle_panel",    label = "Hide panel",     category = "View",    bindings = { "key:h", "pad:back" } },
      { name = "toggle_grid",     label = "Toggle grid",    category = "Effects", bindings = { "key:g", "pad:rightshoulder" } },
      { name = "reset_effects",   label = "Reset effects",  category = "Effects", bindings = { "key:r" } },
      { name = "open_controls",   label = "Key bindings",   category = "System",  bindings = { "key:c", "pad:start" } },
    },
  },
  -- Exported to assets/generated/<name>.png; scripts/release.sh bakes icon/favicon into the builds.
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
})

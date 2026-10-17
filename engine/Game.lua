local Object = require "engine.lib.classic"

local mcpOk, mcp_bridge = pcall(require, "engine.dev.mcp_bridge")
if not mcpOk then mcp_bridge = nil end

local sceneManager = require "engine.sceneManager"
local audioManager = require "engine.audioManager"
local system = require "engine.utils.system"
local cursorManager = require "engine.cursorManager"
local inputMap = require "engine.input.inputMap"
local PostProcessing = require "engine.PostProcessing"
local AssetExporter = require "engine.AssetExporter"
local deviceBackends = require "engine.device.backends"
local filePicker = require "engine.device.filePicker"
local deviceCamera = require "engine.device.camera"
local webWindow = require "engine.device.webWindow"

local DEFAULT_WATCH_DIRS = { "engine", "scenes", "gameObjects", "constants" }

---@class CursorConfig
---@field path string Image path for the cursor
---@field hotX number Hotspot x offset
---@field hotY number Hotspot y offset

---@class GameConfig
---@field title string Window title
---@field env string|nil 'dev' enables hot reload and the MCP bridge
---@field scenes table Array of Scene constructors, registered in order. The first entry's load() runs first, so put asset preloading there.
---@field defaultScene string Name of the scene made current after registration
---@field cursors table<string, CursorConfig>|nil Named cursors. Key "default" is applied at startup if present.
---@field shaders table|nil Array of post-processing shader definitions, applied in order
---@field watch table|nil Directories watched by hot reload in dev (defaults to engine, scenes, gameObjects, constants)
---@field assets AssetConfig|nil Marketing assets rendered by `love . --export-assets` (see engine/AssetExporter.lua)
---@field input InputConfig|nil Named input actions and their default bindings (see engine/input/inputMap.lua)
---@field device DeviceConfig|nil File picker and camera defaults (see engine/device/filePicker.lua)

---@class DeviceConfig
---@field filePicker FilePickerConfig|nil Defaults for engine/device/filePicker.lua
---@field camera DeviceCameraConfig|nil Defaults for engine/device/camera.lua
---@field backend string|nil Force a backend: "null", "mock", "web", "desktop" or "mobile". nil picks from the OS; the examples suite passes "mock".

---@class InputConfig
---@field actions table Array of { name, label, category, bindings = { "key:space", "pad:a", ... } }
---@field deadzone number|nil Stick deadzone 0..1 (default 0.25)
---@field saveFile string|false|nil Save-directory file for custom bindings (default "bindings.lua"; false disables saving)

---@class Game : Object
---@field title string name of the game
---@field env string|nil 'dev' used to enable dev only features
---@field scenes table Scene constructors to register
---@field defaultScene string Starting scene name
---@field cursors table<string, CursorConfig>
---@field shaders table
---@field watch table
---@field assets AssetConfig|nil
---@field device DeviceConfig|nil
---@field args table Command-line arguments passed to love.load
---@field sceneManager table The scene manager
---@field audioManager table the audio manager
---@field cursorManager table cursor manager
---@field filePicker table the device file picker
---@field deviceCamera table the device camera
local Game = Object:extend()

---@param config GameConfig
function Game:new(config)
  assert(type(config) == "table", "Game expects a config table")
  assert(type(config.title) == "string", "Game config requires a title")
  assert(type(config.scenes) == "table" and #config.scenes > 0, "Game config requires a non-empty scenes array")
  assert(type(config.defaultScene) == "string", "Game config requires a defaultScene name")

  self.title = config.title
  self.env = config.env
  self.scenes = config.scenes
  self.defaultScene = config.defaultScene
  self.cursors = config.cursors or {}
  self.shaders = config.shaders or {}
  self.watch = config.watch or DEFAULT_WATCH_DIRS
  self.mcpPort = config.mcpPort
  self.assets = config.assets
  self.input = config.input
  self.device = config.device
  self.args = {}
  self.sceneManager = sceneManager
  self.audioManager = audioManager
  self.cursorManager = cursorManager
  self.inputManager = inputMap
  self.filePicker = filePicker
  self.deviceCamera = deviceCamera
  self.postProcessing = PostProcessing()

  self:initializeEvents()

  return self
end

function Game:initializeEvents()
  function love.load(args)
    self:load(args)
  end

  function love.update(dt)
    self:update(dt)
  end

  function love.draw()
    self:draw()
  end

  function love.mousepressed(x, y, button, istouch, presses)
    self:mousepressed(x, y, button, istouch, presses)
  end

  function love.mousereleased(x, y, button, istouch, presses)
    self:mousereleased(x, y, button, istouch, presses)
  end

  function love.mousemoved(x, y, dx, dy, isTouch)
    self:mousemoved(x, y, dx, dy, isTouch)
  end

  function love.wheelmoved(x, y)
    self:wheelmoved(x, y)
  end

  function love.touchpressed(id, x, y, dx, dy, pressure)
    self:touchpressed(id, x, y, dx, dy, pressure)
  end

  function love.touchmoved(id, x, y, dx, dy, pressure)
    self:touchmoved(id, x, y, dx, dy, pressure)
  end

  function love.touchreleased(id, x, y, dx, dy, pressure)
    self:touchreleased(id, x, y, dx, dy, pressure)
  end

  function love.keypressed(key, scancode, isrepeat)
    self:keypressed(key, scancode, isrepeat)
  end

  function love.keyreleased(key, scancode)
    self:keyreleased(key, scancode)
  end

  function love.gamepadpressed(joystick, button)
    self:gamepadpressed(joystick, button)
  end

  function love.gamepadreleased(joystick, button)
    self:gamepadreleased(joystick, button)
  end

  function love.gamepadaxis(joystick, axis, value)
    self:gamepadaxis(joystick, axis, value)
  end

  function love.filedropped(file)
    self:filedropped(file)
  end

  function love.directorydropped(path)
    self:directorydropped(path)
  end

  function love.threaderror(thread, errorstring)
    self:threaderror(thread, errorstring)
  end

  function love.joystickadded(joystick)
    inputMap.joystickadded(joystick)
  end

  function love.joystickremoved(joystick)
    inputMap.joystickremoved(joystick)
  end

  function love.focus(focused)
    self:focus(focused)
  end

  function love.resize(w, h)
    self:resize(w, h)
  end

  -- The return value matters: a truthy result aborts the quit. Game:quit uses
  -- that on the web build, where a synthetic beforeunload is the save-flush
  -- mechanism rather than a real quit.
  function love.quit()
    return self:quit()
  end
end

--- Whether a flag was passed on the command line, e.g. `love . --export-assets`.
---@param flag string
---@return boolean
function Game:hasArg(flag)
  for _, a in ipairs(self.args) do
    if a == flag then return true end
  end
  return false
end

---@param args table|nil Arguments from love.load
function Game:load(args)
  self.args = args or {}
  if not system.isWeb() then
    -- Restore window position and display if saved
    local pos = love.filesystem.read("windowpos.txt")
    if pos then
      local display, x, y = pos:match("(%d+),(%d+),(%d+)")
      display, x, y = tonumber(display), tonumber(x), tonumber(y)
      if display and x and y then
        local numDisplays = love.window.getDisplayCount and love.window.getDisplayCount() or 1
        if display >= 1 and display <= numDisplays then
          local desktopWidth, desktopHeight =
              love.window.getDesktopDimensions and love.window.getDesktopDimensions(display) or love.graphics.getWidth(),
              love.graphics.getHeight()
          if x >= 0 and y >= 0 and x < desktopWidth and y < desktopHeight then
            love.window.setPosition(x, y, display)
          else
            love.window.setPosition(0, 0, display)
          end
        else
          love.window.setPosition(0, 0, 1)
        end
      end
    end
  end

  -- Set up the window
  love.window.setTitle(self.title)
  love.graphics.setColor(1, 1, 1)
  love.graphics.setFont(love.graphics.newFont(30))
  love.graphics.setLineWidth(5)
  love.graphics.setLineStyle("smooth")
  love.graphics.setBlendMode("alpha")
  love.graphics.setDefaultFilter("nearest", "nearest", 1)

  local cursors = {}
  for key, cursor in pairs(self.cursors) do
    cursors[key] = love.mouse.newCursor(cursor.path, cursor.hotX or 0, cursor.hotY or 0)
  end
  self.cursorManager.new(cursors)
  if cursors.default then
    self.cursorManager.setCursor("default")
  end

  -- Actions must exist before scenes load: addScene runs load() at once and
  -- scenes build prompts from the current bindings and device.
  inputMap.init(self.input)
  if self.env == "dev" and mcp_bridge then
    inputMap.setVirtualInput({
      keyDown = mcp_bridge.isVirtualKeyDown,
      mouseDown = mcp_bridge.isVirtualMouseDown,
    })
  end

  -- Device backends are chosen before scenes load, for the same reason input
  -- is: a scene's load() may ask whether a picker or a camera exists in order
  -- to decide what UI to build.
  local device = self.device or {}
  deviceBackends.init(device.backend)
  filePicker.configure(device.filePicker)
  deviceCamera.configure(device.camera)

  for _, SceneConstructor in ipairs(self.scenes) do
    self.sceneManager.addScene(SceneConstructor)
  end
  self.sceneManager.setCurrentScene(self.defaultScene)

  self.postProcessing:load()
  for _, shaderDef in ipairs(self.shaders) do
    self.postProcessing:addShader(shaderDef)
  end

  -- Asset export runs before any dev tooling so it never binds the MCP port
  -- or starts hot reload, then quits without drawing a frame.
  if self:hasArg("--export-assets") then
    assert(self.assets, "--export-assets passed but no `assets` config was given to Game")
    local outputDir = love.filesystem.getSource() .. "/" .. (self.assets.outputDir or "assets/generated")
    AssetExporter.export(self.assets, outputDir, self.postProcessing)
    love.event.quit()
    return
  end

  if self.env == "dev" then
    local hotReload = require "engine.lib.hotReload"
    hotReload.init(function()
      self.audioManager.stopMusic()
    end)
    for _, dir in ipairs(self.watch) do
      hotReload.watch(dir)
    end

    if mcp_bridge then
      -- Port: Game config mcpPort, then the LOVE_MCP_PORT environment variable, then 12345.
      mcp_bridge.init(self.mcpPort or tonumber(os.getenv("LOVE_MCP_PORT") or "") or 12345)
      mcp_bridge.setObjectGetter(function()
        local scene = sceneManager.getCurrentSceneObject()
        return scene and scene.gameObjects or {}
      end)
    end
  end
end

function Game:update(dt)
  -- Poll input first so pressed()/released() are valid for the whole frame,
  -- then deliver action events before the scene's own update.
  inputMap.update(dt)
  local pressed, pressedCount = inputMap.getPressed()
  for i = 1, pressedCount do
    self.sceneManager.actionPressed(pressed[i])
  end
  local released, releasedCount = inputMap.getReleased()
  for i = 1, releasedCount do
    self.sceneManager.actionReleased(released[i])
  end

  -- Before anything reads the window: on the web the page owns the frame size,
  -- and a scene that lays itself out this frame should do it against the size
  -- it is about to be drawn at, not the one it was a frame ago.
  local resized, windowWidth, windowHeight = webWindow.apply()
  if resized then
    self:resize(windowWidth, windowHeight)
  end

  -- Device results land before the scene updates, so a scene that reads
  -- getTexture() or acts on a picked file sees this frame's value.
  filePicker.update(dt)
  deviceCamera.update(dt)

  self.postProcessing:update(dt)
  self.sceneManager.update(dt)
  -- After the scene so music parameters set this frame reach steps fired this frame.
  self.audioManager.update(dt)

  -- Shader uniforms are rebuilt every frame by the current scene so that
  -- switching scenes never leaves stale values behind.
  local uniforms = self.postProcessing.uniforms
  for key in pairs(uniforms) do
    uniforms[key] = nil
  end
  local scene = self.sceneManager.getCurrentSceneObject()
  if scene and scene.updateShaderUniforms then
    scene:updateShaderUniforms(uniforms, dt)
  end

  if self.env == "dev" then
    local hotReload = require "engine.lib.hotReload"
    hotReload.update()
    if mcp_bridge then mcp_bridge.update() end
  end
end

--- A file was dropped on the window. The device file picker gets first refusal
--- (a drop can answer an open pick), then the scene's optional `filedropped`.
--- @param file love.DroppedFile The dropped file
function Game:filedropped(file)
  if filePicker.filedropped(file) then return end
  self.sceneManager.checkAndCallSceneFunction("filedropped", file)
end

--- A folder was dropped on the window; handed to the current scene.
--- @param path string Absolute path of the dropped directory
function Game:directorydropped(path)
  self.sceneManager.checkAndCallSceneFunction("directorydropped", path)
end

--- A thread died. Offered to the device modules so a dead worker fails the
--- request it was serving instead of leaving it waiting forever; anything else
--- is printed, because an unreported thread error is otherwise silent.
--- @param thread love.Thread The thread that errored
--- @param errorstring string The error it died with
function Game:threaderror(thread, errorstring)
  if filePicker.threaderror(thread, errorstring) then return end
  if deviceCamera.threaderror(thread, errorstring) then return end
  print("Thread error: " .. tostring(errorstring))
end

function Game:draw()
  self.postProcessing:beginCapture()
  self.sceneManager.draw()
  self.postProcessing:endCapture()
  self.postProcessing:apply()
  if mcp_bridge then mcp_bridge.captureIfPending() end
end

function Game:resize(w, h)
  self.postProcessing:resize(w, h)
  self.sceneManager.checkAndCallSceneFunction("resize", w, h)
end

-- Raw events go to inputMap first (rebind capture, active-device tracking,
-- tap latching). A capture in progress consumes the event.

function Game:mousepressed(x, y, button, istouch, presses)
  if inputMap.mousepressed(x, y, button, istouch, presses) then return end
  self.sceneManager.mousePressed(x, y, button, istouch, presses)
end

function Game:mousereleased(x, y, button, istouch, presses)
  if inputMap.mousereleased(x, y, button, istouch, presses) then return end
  if button == 1 then
    self.sceneManager.click(x, y, button, istouch, presses)
  end
end

function Game:mousemoved(x, y, dx, dy, isTouch)
  inputMap.mousemoved(x, y, dx, dy)
  self.sceneManager.mouseMoved(x, y)
end

function Game:wheelmoved(x, y)
  inputMap.wheelmoved(x, y)
  self.sceneManager.wheelMoved(x, y)
end

-- Touch has no inputMap binding kind (it's screen-position-based, not a
-- remappable button/axis), so these go straight to the scene.
function Game:touchpressed(id, x, y, dx, dy, pressure)
  self.sceneManager.touchPressed(id, x, y, dx, dy, pressure)
end

function Game:touchmoved(id, x, y, dx, dy, pressure)
  self.sceneManager.touchMoved(id, x, y, dx, dy, pressure)
end

function Game:touchreleased(id, x, y, dx, dy, pressure)
  self.sceneManager.touchReleased(id, x, y, dx, dy, pressure)
end

function Game:keypressed(key, scancode, isrepeat)
  if inputMap.keypressed(key, scancode, isrepeat) then return end
  self.sceneManager.keypressed(key, scancode, isrepeat)
end

function Game:keyreleased(key, scancode)
  inputMap.keyreleased(key, scancode)
  self.sceneManager.keyreleased(key, scancode)
end

function Game:gamepadpressed(joystick, button)
  inputMap.gamepadpressed(joystick, button)
end

function Game:gamepadreleased(joystick, button)
  inputMap.gamepadreleased(joystick, button)
end

function Game:gamepadaxis(joystick, axis, value)
  inputMap.gamepadaxis(joystick, axis, value)
end

function Game:focus(focused)
  if focused then
    self.cursorManager.resetCursor()
  else
    inputMap.releaseAll()
  end
end

function Game:quit()
  -- Give the current scene a chance to persist state (see Scene.onQuit). Never let a
  -- failing hook block the quit.
  local hookOk, hookErr = pcall(self.sceneManager.checkAndCallSceneFunction, "onQuit")
  if not hookOk then
    print("Scene onQuit failed: " .. tostring(hookErr))
  end
  if not system.isWeb() then
    local x, y, display = love.window.getPosition()
    if not display then display = 1 end
    love.filesystem.write("windowpos.txt", string.format("%d,%d,%d", display, x, y))
  end
  -- On the web build this is not a quit at all. scripts/web/index.html
  -- dispatches a synthetic `beforeunload` on a timer to force love.js to flush
  -- the IndexedDB-backed save directory, and LÖVE answers it by running this
  -- hook. Returning a falsy value lets the quit proceed, which ends the main
  -- loop and freezes the game a few seconds after it loads; returning true
  -- aborts it. The flush itself is love.js's own beforeunload listener and
  -- happens either way, and when the page really does go away the browser
  -- tears everything down regardless, so nothing is leaked by refusing here.
  -- The scene's onQuit above still runs, which is the autosave that flush
  -- exists to persist.
  if system.isWeb() then return true end

  -- Releases the preview texture and closes the devices, which on desktop also
  -- ends any worker thread; a camera left open outlives the window.
  pcall(filePicker.shutdown)
  pcall(deviceCamera.shutdown)
  if mcp_bridge then mcp_bridge.shutdown() end
  print("Goodbye!")
end

return Game

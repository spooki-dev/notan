--- Device camera: a live preview usable as a texture, and still capture.
---
--- Require it as `deviceCamera` so it never reads like engine/Camera.lua, which
--- is the 2D viewport every scene owns:
--- ```lua
--- local deviceCamera = require "engine.device.camera"
--- deviceCamera.start(nil, function(ok, event) ... end)
--- -- then, in draw:
--- local frame = deviceCamera.getTexture()
--- if frame then love.graphics.draw(frame, 0, 0) end
--- ```
---
--- Platform mechanics live in engine/device/backends/. Like
--- engine/saveManager.lua this module never throws for anything environmental:
--- no camera, a denied permission or a dropped stream all report through the
--- callback with a `[camera]` warning printed.
---
--- Preview cost. Without ffi there is no way to move pixels into a texture
--- without building an ImageData, so the design bounds the cost instead: the
--- defaults are 320x240 at 15 fps (about 300 KiB a frame), one love.Image is
--- created for the whole life of the stream and updated in place with
--- replacePixels, and each frame's ImageData is released the moment it has been
--- uploaded so the big buffers never reach the collector. Raise `width`,
--- `height` and `fps` deliberately: the cost is linear in all three.

local backends = require "engine.device.backends"
local decode = require "engine.device.decode"
local deliver = require "engine.device.deliver"
local sceneManager = require "engine.sceneManager"

local deviceCamera = {}

---@class DeviceCameraConfig
---@field width number|nil Preview width in pixels (default 320)
---@field height number|nil Preview height in pixels (default 240)
---@field fps number|nil Preview frames per second (default 15)
---@field facing string|nil "front" or "back" (default "back")
---@field deviceId string|nil A specific camera from listDevices
---@field maxBytes number|nil Largest acceptable still (default 16 MiB)
---@field saveDir string|nil Save-directory folder for capture deliver = "file"

local DEFAULT_MAX_BYTES = 16 * 1024 * 1024
local VALID_DELIVER = { image = true, bytes = true, file = true }
local VALID_FACING = { front = true, back = true }

local config = {
  width = 320,
  height = 240,
  fps = 15,
  facing = "back",
  deviceId = nil,
  maxBytes = DEFAULT_MAX_BYTES,
  saveDir = "imported",
}

local running = nil      -- { id, callback, width, height }
local capturing = nil    -- { id, callback, options }
local deferred, deferredCount = {}, 0   -- callbacks owed, delivered from update
local state = "idle"
local frameImage = nil
local frameNumber = 0
local available = nil    -- cached tri-state, nil until first asked
local nextId = 0

local function warn(message)
  print("[camera] " .. message)
end

--- Overrides the defaults, usually from the `device.camera` block of the Game
--- config. Any subset of the keys. Takes effect on the next `start`.
--- @param opts DeviceCameraConfig|table|nil
function deviceCamera.configure(opts)
  if type(opts) ~= "table" then return end
  if opts.width ~= nil then
    assert(type(opts.width) == "number" and opts.width > 0, "camera: width must be a positive number")
    config.width = math.floor(opts.width)
  end
  if opts.height ~= nil then
    assert(type(opts.height) == "number" and opts.height > 0, "camera: height must be a positive number")
    config.height = math.floor(opts.height)
  end
  if opts.fps ~= nil then
    assert(type(opts.fps) == "number" and opts.fps > 0, "camera: fps must be a positive number")
    config.fps = opts.fps
  end
  if opts.facing ~= nil then
    assert(VALID_FACING[opts.facing], "camera: facing must be 'front' or 'back'")
    config.facing = opts.facing
  end
  if opts.deviceId ~= nil then
    assert(type(opts.deviceId) == "string", "camera: deviceId must be a string")
    config.deviceId = opts.deviceId
  end
  if opts.maxBytes ~= nil then
    assert(type(opts.maxBytes) == "number" and opts.maxBytes > 0, "camera: maxBytes must be a positive number")
    config.maxBytes = opts.maxBytes
  end
  if opts.saveDir ~= nil then
    assert(type(opts.saveDir) == "string" and opts.saveDir ~= "", "camera: saveDir must be a non-empty string")
    config.saveDir = opts.saveDir
  end
end

--- Whether this platform can open a camera. Cached after the first call.
--- @return boolean
function deviceCamera.isAvailable()
  if available == nil then
    available = backends.get().camera.isAvailable() == true
    if not available then
      warn("no camera on this platform; the camera is disabled")
    end
  end
  return available
end

--- What this platform's camera can do: `preview`, `capture`, `facingSwitch` and
--- `needsGesture`. Gate UI on these rather than on the OS.
--- @return table
function deviceCamera.getCapabilities()
  return backends.get().camera.getCapabilities()
end

--- The cameras this platform can see.
--- @return table Array of { id = string, name = string, facing = string|nil }
function deviceCamera.listDevices()
  return backends.get().camera.listDevices()
end

--- Whether a stream is open. True from the moment `start` succeeds, before the
--- first frame arrives.
--- @return boolean
function deviceCamera.isRunning()
  return running ~= nil
end

--- A finer-grained view than isRunning: "idle", "awaitingGesture", "starting",
--- "running" or "denied". `awaitingGesture` happens on web, where the browser
--- will not grant the camera except from a player's tap, so the page shows a
--- button and the game should prompt for it; it never occurs natively.
--- `starting` covers the gap between `start` returning and the first
--- acknowledgement, which on Android spans the permission dialog.
--- @return string
function deviceCamera.getState()
  return state
end

-- Callbacks are never run from inside `start` or `capture`: they are queued
-- here and delivered from `update`, so every call site has one code path
-- whether the answer took a frame or a permission dialog.
local function defer(callback, a, b, c)
  if not callback then return end
  deferredCount = deferredCount + 1
  deferred[deferredCount] = { callback = callback, a = a, b = b, c = c }
end

--- The newest preview frame, or nil before the first one arrives. The same
--- Image is returned every frame, so hold on to it freely but never release it;
--- `stop` does that.
--- @return love.Image|nil image
--- @return number width Zero when there is no frame yet
--- @return number height Zero when there is no frame yet
function deviceCamera.getTexture()
  if not frameImage then return nil, 0, 0 end
  return frameImage, frameImage:getWidth(), frameImage:getHeight()
end

--- How many frames have arrived since `start`. Monotonic, resets on `start`.
--- Compare it against the value you last saw to know whether the texture
--- changed, without touching the pixels.
--- @return number
function deviceCamera.getFrameNumber()
  return frameNumber
end

--- Opens the camera. Returns at once; `callback` fires on a later frame with
--- `(ok, event, err)` where event is "started", "denied", "error" or
--- "unavailable". Frames then appear through `getTexture`.
--- @param opts table|nil { width, height, fps, facing, deviceId }
--- @param callback fun(ok: boolean, event: string, err: string|nil)|nil
--- @return boolean ok False when a stream is already open or none is possible
--- @return string|nil err
function deviceCamera.start(opts, callback)
  opts = opts or {}
  if callback ~= nil then
    assert(type(callback) == "function", "camera.start: callback must be a function")
  end
  if opts.facing ~= nil then
    assert(VALID_FACING[opts.facing], "camera.start: facing must be 'front' or 'back'")
  end

  if running then
    return false, "the camera is already running"
  end
  if not deviceCamera.isAvailable() then
    defer(callback, false, "unavailable", "no camera on this platform")
    return false, "no camera on this platform"
  end

  nextId = nextId + 1
  local request = {
    id = nextId,
    width = math.floor(opts.width or config.width),
    height = math.floor(opts.height or config.height),
    fps = opts.fps or config.fps,
    facing = opts.facing or config.facing,
    deviceId = opts.deviceId or config.deviceId,
  }

  local ok, err = backends.get().camera.start(request)
  if not ok then
    defer(callback, false, "error", err or "the camera could not be opened")
    return false, err
  end

  running = { id = request.id, callback = callback, width = request.width, height = request.height }
  state = "starting"
  frameNumber = 0
  return true
end

--- Closes the stream and frees the preview texture. Safe to call when nothing
--- is running. Does not fire the start callback.
function deviceCamera.stop()
  if running then
    backends.get().camera.stop()
    running = nil
  end
  if frameImage then
    frameImage:release()
    frameImage = nil
  end
  state = "idle"
  frameNumber = 0
end

--- Captures one still at the best resolution the device offers, independently
--- of the preview size. `callback` receives `(result, event, err)` with the same
--- result shapes as engine/device/filePicker.lua.
--- @param opts table|nil { deliver, saveAs, maxBytes }
--- @param callback fun(result: DevicePickResult|nil, event: string, err: string|nil)
--- @return boolean ok
--- @return string|nil err
function deviceCamera.capture(opts, callback)
  assert(type(callback) == "function", "camera.capture: a callback is required")
  opts = opts or {}
  if opts.deliver ~= nil then
    assert(VALID_DELIVER[opts.deliver], "camera.capture: deliver must be 'image', 'bytes' or 'file'")
  end

  if capturing then
    return false, "a capture is already in flight"
  end
  if not deviceCamera.isAvailable() then
    defer(callback, nil, "unavailable", "no camera on this platform")
    return false, "no camera on this platform"
  end

  nextId = nextId + 1
  local request = {
    id = nextId,
    width = config.width,
    height = config.height,
    fps = config.fps,
    facing = config.facing,
    deviceId = config.deviceId,
  }

  local ok, err = backends.get().camera.capture(request)
  if not ok then
    defer(callback, nil, "error", err or "the camera could not capture")
    return false, err
  end

  capturing = {
    id = request.id,
    callback = callback,
    options = {
      deliver = opts.deliver or "image",
      maxBytes = opts.maxBytes or config.maxBytes,
      saveAs = opts.saveAs,
      saveDir = config.saveDir,
    },
  }
  return true
end

-- Uploads one raw RGBA frame into the reused texture. Failures warn once per
-- frame and leave the previous texture in place rather than tearing the stream
-- down: a dropped frame is not a dropped camera.
local function acceptFrame(event)
  local imageData, err = decode.imageDataFromRGBA(event.bytes, event.width, event.height)
  if not imageData then
    warn("dropped a frame: " .. tostring(err))
    return
  end
  local image, uploadErr = decode.uploadToImage(frameImage, imageData)
  imageData:release()
  if not image then
    warn("dropped a frame: " .. tostring(uploadErr))
    return
  end
  frameImage = image
  frameNumber = frameNumber + 1
end

-- Fires the start callback once, clearing it first so the callback may stop and
-- restart the camera, and wrapping it so a failing game callback cannot take
-- the frame down.
local function finishStart(ok, event, err)
  local callback = running and running.callback
  if running then running.callback = nil end
  defer(callback, ok, event, err)
  sceneManager.checkAndCallSceneFunction("onCameraStarted", ok, event, err)
end

local function finishCapture(result, event, err)
  local callback = capturing.callback
  capturing = nil
  defer(callback, result, event, err)
  sceneManager.checkAndCallSceneFunction("onCameraCaptured", result, event, err)
end

-- Runs the callbacks owed, taking the list first so a callback that restarts
-- the camera cannot extend the batch being delivered.
local function deliverDeferred()
  if deferredCount == 0 then return end
  local batch, count = deferred, deferredCount
  deferred, deferredCount = {}, 0
  for i = 1, count do
    local entry = batch[i]
    local ok, err = pcall(entry.callback, entry.a, entry.b, entry.c)
    if not ok then
      warn("callback failed: " .. tostring(err))
    end
  end
end

--- Releases whatever the backend holds and stops the stream. Called from
--- Game:quit.
function deviceCamera.shutdown()
  deviceCamera.stop()
  local ok, err = pcall(function()
    backends.get().camera.shutdown()
  end)
  if not ok then
    warn("shutdown failed: " .. tostring(err))
  end
end

--- Reports a worker thread that died, from Game's love.threaderror. When the
--- backend claims the thread, the stream is torn down and the start callback,
--- if one is still owed, fails.
--- @param thread love.Thread The thread that errored
--- @param errorString string The error it died with
--- @return boolean handled
function deviceCamera.threaderror(thread, errorString)
  local ok, handled = pcall(function()
    return backends.get().camera.threaderror(thread, errorString)
  end)
  if not ok or not handled then return false end
  available = nil
  if running then
    finishStart(false, "error", tostring(errorString))
  end
  deviceCamera.stop()
  state = "idle"
  return true
end

--- Drains the backend. Called once per frame by Game:update; a game that builds
--- its own loop must call it too or no frames arrive.
--- @param dt number Seconds since the last frame
function deviceCamera.update(dt)
  local backend = backends.get().camera
  backend.tick(dt)
  local event = backend.poll()
  while event do
    if event.status == "frame" then
      if running and event.id == running.id then
        acceptFrame(event)
        state = "running"
      end
    elseif event.status == "state" then
      -- Not terminal: a platform telling us it is waiting for a tap.
      if running then state = event.state or state end
    elseif event.status == "started" then
      if running and event.id == running.id then
        state = "running"
        finishStart(true, "started")
      end
    elseif event.status == "denied" or event.status == "error" then
      if running and event.id == running.id then
        local status = event.status
        local err = event.err or (status == "denied" and "the player denied camera access" or "the camera failed")
        finishStart(false, status, err)
        deviceCamera.stop()
        state = status
      end
    elseif event.status == "still" then
      if capturing and event.id == capturing.id then
        local result, err = deliver.one(event, capturing.options)
        if result then
          finishCapture(result, "picked")
        else
          warn(err)
          finishCapture(nil, "error", err)
        end
      end
    end
    event = backend.poll()
  end
  deliverDeferred()
end

return deviceCamera

--- The love.js web build.
---
--- Both features are driven from the page, because the love.js runtime has no
--- video capture and no way to open a dialog: the Lua side only sends commands
--- and reads back bytes. See engine/device/webBridge.lua for the channel and
--- scripts/web/index.html for the page half.
---
--- The one thing a game must handle here is the gesture. Browsers refuse to
--- open a file dialog or grant a camera except from a real user activation, and
--- a command arriving over the bridge runs inside the wasm main loop, which is
--- not one. So a request is *armed* rather than opened: the page shows an
--- overlay the player taps, and the dialog opens from that tap's handler. The
--- front end reports this as `getState() == "awaitingGesture"` and
--- `getCapabilities().needsGesture`, so a game can word its prompt for it.

local system = require "engine.utils.system"
local webBridge = require "engine.device.webBridge"
local deliver = require "engine.device.deliver"

local web = {}

web.name = "web"

local pickEvents, pickCount = {}, 0
local cameraEvents, cameraCount = {}, 0
local available = nil
local cameraRequest = nil

local function warn(message)
  print("[device:web] " .. message)
end

local function isAvailable()
  if available == nil then
    available = system.isWeb() and webBridge.isAvailable()
    if not available and system.isWeb() then
      warn("the page bridge did not answer; scripts/web/index.html may be out of date")
    end
  end
  return available
end

local function pushPick(event)
  pickCount = pickCount + 1
  pickEvents[pickCount] = event
end

local function pushCamera(event)
  cameraCount = cameraCount + 1
  cameraEvents[cameraCount] = event
end

-- Both features read the same event file, so one reader fans every line out to
-- the right queue. Anything unrecognised is ignored rather than warned about:
-- a newer page may post events an older engine does not know.
local function drainEvents()
  local events = webBridge.readEvents()
  for _, event in ipairs(events) do
    local id = tonumber(event.id)
    local kind = event.kind
    if kind == "state" then
      pushPick({ id = id, status = "state", state = event.state })
      pushCamera({ id = id, status = "state", state = event.state })
    elseif kind == "picked" then
      local bytes = webBridge.readBlob(event.blob)
      if bytes then
        pushPick({ id = id, status = "picked", bytes = bytes, name = event.name,
          mime = event.mime ~= "" and event.mime or deliver.mimeFor(event.name) })
      else
        pushPick({ id = id, status = "error", err = "the page could not hand over the file" })
      end
    elseif kind == "cancelled" then
      pushPick({ id = id, status = "cancelled" })
    elseif kind == "error" then
      pushPick({ id = id, status = "error", err = event.err })
    elseif kind == "camstarted" then
      pushCamera({ id = id, status = "started" })
    elseif kind == "camdenied" then
      pushCamera({ id = id, status = "denied", err = event.err })
    elseif kind == "camerror" then
      pushCamera({ id = id, status = "error", err = event.err })
    elseif kind == "still" then
      local bytes = webBridge.readBlob(event.blob)
      if bytes then
        pushCamera({ id = id, status = "still", bytes = bytes, name = event.name,
          mime = event.mime ~= "" and event.mime or deliver.mimeFor(event.name) })
      else
        pushCamera({ id = id, status = "error", err = "the page could not hand over the still" })
      end
    end
  end
end

web.filePicker = {}

--- @return boolean
function web.filePicker.isAvailable()
  return isAvailable()
end

--- @return table
function web.filePicker.getCapabilities()
  return {
    pick = isAvailable(),
    multiple = true,
    acceptFilter = true,
    -- `capture` on a file input opens the camera app directly on a phone.
    fromCamera = true,
    -- The whole reason this backend arms rather than opens.
    needsGesture = true,
    dragDrop = false,
  }
end

--- @param request DevicePickRequest
--- @return boolean ok
--- @return string|nil err
function web.filePicker.open(request)
  if not isAvailable() then
    return false, "the page bridge is unavailable"
  end
  local accept = ""
  if type(request.accept) == "table" then
    accept = table.concat(request.accept, ",")
  end
  webBridge.send("pick", {
    id = request.id,
    accept = accept,
    multiple = request.multiple and 1 or 0,
    source = request.source or "files",
  })
  return true
end

function web.filePicker.cancel()
  if isAvailable() then
    webBridge.send("cancelpick", {})
  end
  pickEvents, pickCount = {}, 0
end

--- @param dt number
function web.filePicker.tick(dt) -- luacheck: ignore dt
  if isAvailable() then drainEvents() end
end

--- @return DevicePickEvent|nil
function web.filePicker.poll()
  if pickCount == 0 then return nil end
  local event = pickEvents[1]
  table.remove(pickEvents, 1)
  pickCount = pickCount - 1
  return event
end

function web.filePicker.shutdown()
  pickEvents, pickCount = {}, 0
  webBridge.reset()
  available = nil
end

web.camera = {}

--- @return boolean
function web.camera.isAvailable()
  return isAvailable()
end

--- @return table
function web.camera.getCapabilities()
  return {
    preview = isAvailable(),
    capture = isAvailable(),
    facingSwitch = true,
    needsGesture = true,
  }
end

--- The page cannot enumerate cameras before permission is granted (browsers
--- hide the labels), and after it is granted the facing option covers what a
--- game actually wants, so this stays empty.
--- @return table
function web.camera.listDevices()
  return {}
end

--- @param request DeviceCameraRequest
--- @return boolean ok
--- @return string|nil err
function web.camera.start(request)
  if not isAvailable() then
    return false, "the page bridge is unavailable"
  end
  cameraRequest = request
  webBridge.send("camstart", {
    id = request.id,
    w = request.width,
    h = request.height,
    fps = request.fps,
    facing = request.facing or "back",
  })
  return true
end

function web.camera.stop()
  if isAvailable() then
    webBridge.send("camstop", {})
  end
  cameraRequest = nil
  cameraEvents, cameraCount = {}, 0
end

--- @param request DeviceCameraRequest
--- @return boolean ok
--- @return string|nil err
function web.camera.capture(request)
  if not isAvailable() then
    return false, "the page bridge is unavailable"
  end
  webBridge.send("camstill", { id = request.id })
  return true
end

--- @param dt number
function web.camera.tick(dt) -- luacheck: ignore dt
  if not isAvailable() then return end
  drainEvents()
  if not cameraRequest then return end
  -- At most one frame per tick, and always the newest: the page overwrites the
  -- buffer in place, so an unread frame is simply gone rather than queued.
  local bytes, width, height = webBridge.readFrame()
  if bytes then
    pushCamera({ id = cameraRequest.id, status = "frame", bytes = bytes, width = width, height = height })
  end
end

--- @return DeviceCameraEvent|nil
function web.camera.poll()
  if cameraCount == 0 then return nil end
  local event = cameraEvents[1]
  table.remove(cameraEvents, 1)
  cameraCount = cameraCount - 1
  return event
end

function web.camera.shutdown()
  web.camera.stop()
  available = nil
end

return web

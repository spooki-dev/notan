--- Deterministic stand-in for a real device, selected with
--- `device = { backend = "mock" }` in the Game config.
---
--- It exists so the public API in engine/device/filePicker.lua and
--- engine/device/camera.lua can be exercised headlessly: the examples
--- catalogue (and therefore scripts/test.sh and CI) drives the real front ends
--- against this backend, so open/cancel ordering, the three delivery modes,
--- frame numbering and capability degradation are all covered by the suite on a
--- machine with no camera and no window manager. Everything it produces is a
--- pure function of the request and a frame counter, so golden screenshots are
--- stable.
---
--- The same idea as the virtual input the MCP bridge hands to inputMap (see
--- engine/Game.lua): the engine stays free of test scaffolding because the
--- substitution happens at the backend seam.

local mock = {}

mock.name = "mock"

local PICK_SIZE = 64        -- the generated image is PICK_SIZE square
local PICK_CHECKER = 8      -- checker square in pixels
local BAND_COUNT = 8        -- vertical colour bands in a camera frame

-- Band colours, cycled by frame number. Opaque, and far enough apart that a
-- snapshot diff catches a wrong row stride or a swapped channel.
local BANDS = {
  { 255, 0, 0 }, { 255, 160, 0 }, { 255, 255, 0 }, { 0, 200, 0 },
  { 0, 160, 255 }, { 60, 60, 220 }, { 170, 0, 220 }, { 240, 240, 240 },
}

local nextResult = "picked"
local pickEvents, pickCount = {}, 0
local cameraEvents, cameraCount = {}, 0
local pickBytes = nil
local running = nil        -- the active camera request
local frameCounter = 0
local frameClock = 0       -- seconds owed to the next frame, so fps is honoured

--- Forces what the next pick resolves to, so an example can exercise the
--- cancel and error paths as well as the happy one.
--- @param status string "picked", "cancelled" or "error"
function mock.setNextResult(status)
  assert(status == "picked" or status == "cancelled" or status == "error",
    "mock.setNextResult: status must be picked, cancelled or error")
  nextResult = status
end

--- Clears every queue and counter. The examples runner purges package.loaded
--- between examples so this is only needed inside a single example.
function mock.reset()
  nextResult = "picked"
  pickEvents, pickCount = {}, 0
  cameraEvents, cameraCount = {}, 0
  running = nil
  frameCounter = 0
end

-- A PNG of a two-tone checkerboard, built once. Encoded rather than handed
-- over raw because that is what a real picker returns: it keeps the front end's
-- decode path on the same code the device backends use.
local function getPickBytes()
  if pickBytes then return pickBytes end
  local imageData = love.image.newImageData(PICK_SIZE, PICK_SIZE)
  imageData:mapPixel(function(x, y)
    local dark = (math.floor(x / PICK_CHECKER) + math.floor(y / PICK_CHECKER)) % 2 == 0
    if dark then
      return 0.11, 0.11, 0.16, 1
    end
    return 0.78, 0.72, 0.75, 1
  end)
  pickBytes = imageData:encode("png"):getString()
  imageData:release()
  return pickBytes
end

-- One frame of colour bands over a darker lower third. Built from string.rep so
-- a 320x240 frame costs a handful of concatenations rather than 76800 of them.
local function buildFrame(width, height, counter)
  local bandWidth = math.max(1, math.floor(width / BAND_COUNT))
  local top, bottom = {}, {}
  local used = 0
  for i = 1, BAND_COUNT do
    local w = (i == BAND_COUNT) and (width - used) or bandWidth
    used = used + w
    local band = BANDS[((i - 1 + counter) % #BANDS) + 1]
    top[i] = string.rep(string.char(band[1], band[2], band[3], 255), w)
    bottom[i] = string.rep(string.char(
      math.floor(band[1] * 0.35), math.floor(band[2] * 0.35), math.floor(band[3] * 0.35), 255), w)
  end
  local topRow = table.concat(top)
  local bottomRow = table.concat(bottom)
  local split = math.floor(height * 2 / 3)
  return string.rep(topRow, split) .. string.rep(bottomRow, height - split)
end

local function pushPick(event)
  pickCount = pickCount + 1
  pickEvents[pickCount] = event
end

mock.filePicker = {}

function mock.filePicker.isAvailable()
  return true
end

function mock.filePicker.getCapabilities()
  return {
    pick = true, multiple = true, acceptFilter = true,
    fromCamera = true, needsGesture = false, dragDrop = false,
  }
end

function mock.filePicker.open(request)
  if nextResult == "cancelled" then
    pushPick({ id = request.id, status = "cancelled" })
  elseif nextResult == "error" then
    pushPick({ id = request.id, status = "error", err = "mock failure" })
  elseif request.multiple then
    local bytes = getPickBytes()
    pushPick({
      id = request.id,
      status = "picked",
      files = {
        { bytes = bytes, name = "mock-1.png", mime = "image/png" },
        { bytes = bytes, name = "mock-2.png", mime = "image/png" },
      },
    })
  else
    pushPick({ id = request.id, status = "picked", bytes = getPickBytes(), name = "mock.png", mime = "image/png" })
  end
  return true
end

function mock.filePicker.cancel()
  pickEvents, pickCount = {}, 0
end

function mock.filePicker.poll()
  if pickCount == 0 then return nil end
  local event = pickEvents[1]
  table.remove(pickEvents, 1)
  pickCount = pickCount - 1
  return event
end

mock.camera = {}

function mock.camera.isAvailable()
  return true
end

function mock.camera.getCapabilities()
  return { preview = true, capture = true, facingSwitch = true, needsGesture = false }
end

function mock.camera.listDevices()
  return {
    { id = "mock-back", name = "Mock rear camera", facing = "back" },
    { id = "mock-front", name = "Mock front camera", facing = "front" },
  }
end

function mock.camera.start(request)
  running = request
  frameCounter = 0
  frameClock = 0
  cameraCount = cameraCount + 1
  cameraEvents[cameraCount] = { id = request.id, status = "started" }
  return true
end

function mock.camera.stop()
  running = nil
  frameClock = 0
  cameraEvents, cameraCount = {}, 0
end

-- Produces at most one frame per tick, paced by the requested fps. With the
-- examples runner's fixed 1/60 dt this makes frame arrival deterministic: at
-- the default 15 fps a frame lands on every fourth update.
function mock.camera.tick(dt)
  if not running then return end
  frameClock = frameClock + (dt or 0)
  local interval = 1 / math.max(1, running.fps or 15)
  if frameClock < interval then return end
  frameClock = frameClock - interval
  frameCounter = frameCounter + 1
  -- Coalesce: drop a frame the front end has not taken yet.
  for i = cameraCount, 1, -1 do
    if cameraEvents[i].status == "frame" then
      table.remove(cameraEvents, i)
      cameraCount = cameraCount - 1
    end
  end
  cameraCount = cameraCount + 1
  cameraEvents[cameraCount] = {
    id = running.id,
    status = "frame",
    bytes = buildFrame(running.width, running.height, frameCounter),
    width = running.width,
    height = running.height,
  }
end

function mock.camera.capture(request)
  cameraCount = cameraCount + 1
  cameraEvents[cameraCount] = {
    id = request.id,
    status = "still",
    bytes = getPickBytes(),
    name = "mock-still.png",
    mime = "image/png",
  }
  return true
end

function mock.camera.poll()
  if cameraCount == 0 then return nil end
  local event = cameraEvents[1]
  table.remove(cameraEvents, 1)
  cameraCount = cameraCount - 1
  return event
end

return mock

--- Lets the player pick a file from their device through the real OS or browser
--- picker, and hands it to the game in whichever shape the game asked for.
---
--- This is not programmatic file access: it always opens a picker the player
--- drives. Platform mechanics live in engine/device/backends/; this module owns
--- the config, the request in flight, the delivery conversion and the callback.
---
--- Like engine/saveManager.lua it never throws for anything environmental: no
--- picker, a denied permission, a corrupt file or a store that will not accept
--- a write all report through the callback, with a `[filePicker]` warning
--- printed. Only misuse of the API itself (a bad `deliver` mode, a missing
--- callback) asserts.
---
--- Usage:
--- ```lua
--- local filePicker = require "engine.device.filePicker"
--- filePicker.open({ deliver = "image" }, function(result, event)
---   if event == "picked" then self.portrait = result.image end
--- end)
--- ```
---
--- The result arrives on a later frame, never inside `open`. On web the picker
--- must be opened from a user gesture, so `getCapabilities().needsGesture` is
--- true there and the page shows a button the player taps; word any in-game
--- prompt from that flag rather than assuming the picker opens at once.

local backends = require "engine.device.backends"
local deliver = require "engine.device.deliver"
local sceneManager = require "engine.sceneManager"

local filePicker = {}

---@class FilePickerConfig
---@field deliver string|nil "image" (default), "bytes" or "file"
---@field accept table|nil MIME patterns or extensions, e.g. { "image/*" }
---@field maxBytes number|nil Reject anything larger (default 16 MiB)
---@field saveDir string|nil Save-directory folder for deliver = "file" (default "imported")
---@field allowDrop boolean|nil Let a file dropped on the window answer an open pick (default true; desktop only)

---@class DevicePickResult
---@field image love.Image|nil deliver = "image": the decoded, drawable image
---@field width number|nil deliver = "image": image width in pixels
---@field height number|nil deliver = "image": image height in pixels
---@field bytes string|nil deliver = "bytes": the file contents
---@field path string|nil deliver = "file": path relative to the save directory
---@field name string|nil File name as the device reported it (nil for a multiple pick)
---@field mime string|nil MIME type when the platform supplies one
---@field size number Size in bytes
---@field files table|nil With multiple = true, the array of per-file results

local DEFAULT_MAX_BYTES = 16 * 1024 * 1024
local VALID_DELIVER = { image = true, bytes = true, file = true }
local VALID_SOURCE = { files = true, camera = true }

local config = {
  deliver = "image",
  accept = nil,
  maxBytes = DEFAULT_MAX_BYTES,
  saveDir = "imported",
  allowDrop = true,
}

local pending = nil      -- the request in flight: { id, callback, options }
local injected, injectedCount = {}, 0   -- events from outside a backend (drag and drop)
local deferred, deferredCount = {}, 0   -- callbacks owed, delivered from update
local state = "idle"
local nextId = 0
local available = nil    -- cached tri-state, nil until first asked

local function warn(message)
  print("[filePicker] " .. message)
end

--- Overrides the defaults, usually from the `device.filePicker` block of the
--- Game config. Any subset of the keys; anything else is left alone.
--- @param opts FilePickerConfig|table|nil
function filePicker.configure(opts)
  if type(opts) ~= "table" then return end
  if opts.deliver ~= nil then
    assert(VALID_DELIVER[opts.deliver], "filePicker: deliver must be 'image', 'bytes' or 'file'")
    config.deliver = opts.deliver
  end
  if opts.accept ~= nil then
    assert(type(opts.accept) == "table", "filePicker: accept must be an array of patterns")
    config.accept = opts.accept
  end
  if opts.maxBytes ~= nil then
    assert(type(opts.maxBytes) == "number" and opts.maxBytes > 0, "filePicker: maxBytes must be a positive number")
    config.maxBytes = opts.maxBytes
  end
  if opts.saveDir ~= nil then
    assert(type(opts.saveDir) == "string" and opts.saveDir ~= "", "filePicker: saveDir must be a non-empty string")
    config.saveDir = opts.saveDir
  end
  if opts.allowDrop ~= nil then
    assert(type(opts.allowDrop) == "boolean", "filePicker: allowDrop must be a boolean")
    config.allowDrop = opts.allowDrop
  end
end

--- Whether this platform can show a picker. Cached after the first call.
--- @return boolean
function filePicker.isAvailable()
  if available == nil then
    available = backends.get().filePicker.isAvailable() == true
    if not available then
      warn("no file picker on this platform; picking is disabled")
    end
  end
  return available
end

--- What this platform's picker can do: `pick`, `multiple`, `acceptFilter`,
--- `fromCamera` and `needsGesture`. Gate UI on these rather than on the OS.
--- @return table
function filePicker.getCapabilities()
  return backends.get().filePicker.getCapabilities()
end

--- Whether a pick is in flight.
--- @return boolean
function filePicker.isOpen()
  return pending ~= nil
end

--- A finer-grained view than isOpen: "idle", "awaitingGesture", "open" or
--- "loading". `awaitingGesture` happens on web, where the browser will not open
--- a dialog except from a player's tap, so the page shows a button and the game
--- should prompt for it. It never occurs on a native platform.
--- @return string
function filePicker.getState()
  return state
end

-- Callbacks are never run from inside `open`: they are queued here and
-- delivered from `update`, so every call site has one code path whether the
-- answer took a frame or a minute.
local function defer(callback, result, event, err)
  deferredCount = deferredCount + 1
  deferred[deferredCount] = { callback = callback, result = result, event = event, err = err }
end

--- Opens the picker. Returns at once; `callback` fires on a later frame with
--- `(result, event, err)` where event is "picked", "cancelled", "error" or
--- "unavailable". Only one pick may be in flight at a time.
--- @param opts table|nil { deliver, accept, multiple, maxBytes, saveAs, source }
--- @param callback fun(result: DevicePickResult|nil, event: string, err: string|nil)
--- @return boolean ok False when a pick is already in flight or none is possible
--- @return string|nil err
function filePicker.open(opts, callback)
  assert(type(callback) == "function", "filePicker.open: a callback is required")
  opts = opts or {}
  if opts.deliver ~= nil then
    assert(VALID_DELIVER[opts.deliver], "filePicker.open: deliver must be 'image', 'bytes' or 'file'")
  end
  if opts.source ~= nil then
    assert(VALID_SOURCE[opts.source], "filePicker.open: source must be 'files' or 'camera'")
  end

  if pending then
    return false, "a pick is already in flight"
  end
  if not filePicker.isAvailable() then
    defer(callback, nil, "unavailable", "no file picker on this platform")
    return false, "no file picker on this platform"
  end

  nextId = nextId + 1
  local request = {
    id = nextId,
    deliver = opts.deliver or config.deliver,
    accept = opts.accept or config.accept,
    multiple = opts.multiple == true,
    maxBytes = opts.maxBytes or config.maxBytes,
    source = opts.source or "files",
  }
  pending = {
    id = request.id,
    callback = callback,
    options = {
      deliver = request.deliver,
      maxBytes = request.maxBytes,
      saveAs = opts.saveAs,
      saveDir = config.saveDir,
    },
  }

  local ok, err = backends.get().filePicker.open(request)
  if not ok then
    pending = nil
    defer(callback, nil, "error", err or "the picker could not be opened")
    return false, err
  end
  state = "open"
  return true
end

--- Abandons the pick in flight. The callback still fires, with
--- `(nil, "cancelled")`, so a caller never waits forever.
function filePicker.cancel()
  if not pending then return end
  local callback = pending.callback
  pending = nil
  state = "idle"
  backends.get().filePicker.cancel()
  defer(callback, nil, "cancelled")
end

-- Finishes the request in flight. Clears `pending` before calling back so the
-- callback may start another pick, matching inputMap.startCapture, and wraps
-- the call so a failing game callback cannot take the frame down.
local function finish(result, event, err)
  local callback = pending.callback
  pending = nil
  state = "idle"
  defer(callback, result, event, err)
end

-- Runs the callbacks owed, taking the list first so a callback that starts
-- another pick cannot extend the batch being delivered. Each is wrapped: work
-- here is game code, and a failing game callback must not take the frame down.
local function deliverDeferred()
  if deferredCount == 0 then return end
  local batch, count = deferred, deferredCount
  deferred, deferredCount = {}, 0
  for i = 1, count do
    local entry = batch[i]
    local ok, err = pcall(entry.callback, entry.result, entry.event, entry.err)
    if not ok then
      warn("callback failed: " .. tostring(err))
    end
    sceneManager.checkAndCallSceneFunction("onFilePicked", entry.result, entry.event, entry.err)
  end
end

--- Releases whatever the backend holds (on desktop, any dialog worker). Called
--- from Game:quit. A pick in flight is cancelled, so its callback still fires.
function filePicker.shutdown()
  filePicker.cancel()
  local ok, err = pcall(function()
    backends.get().filePicker.shutdown()
  end)
  if not ok then
    warn("shutdown failed: " .. tostring(err))
  end
  injected, injectedCount = {}, 0
end

--- Reports a worker thread that died, from Game's love.threaderror. When the
--- backend claims the thread, the pick in flight is failed rather than left to
--- wait for an answer that will never come.
--- @param thread love.Thread The thread that errored
--- @param errorString string The error it died with
--- @return boolean handled
function filePicker.threaderror(thread, errorString)
  local ok, handled = pcall(function()
    return backends.get().filePicker.threaderror(thread, errorString)
  end)
  if not ok or not handled then return false end
  available = nil
  if pending then
    injectedCount = injectedCount + 1
    injected[injectedCount] = { id = pending.id, status = "error", err = tostring(errorString) }
  end
  return true
end

--- Answers an open pick with a file the player dropped on the window. Called by
--- Game from love.filedropped. Returns false when nothing is waiting or
--- `allowDrop` is off, so the drop can be offered to the scene instead.
--- @param file love.DroppedFile The dropped file
--- @return boolean consumed
function filePicker.filedropped(file)
  if not pending or not config.allowDrop then return false end
  local ok, bytes = pcall(function()
    local opened, err = file:open("r")
    if not opened then error(err or "could not open the dropped file") end
    local data = file:read()
    file:close()
    return data
  end)
  if not ok then
    warn("dropped file unreadable: " .. tostring(bytes))
    injectedCount = injectedCount + 1
    injected[injectedCount] = { id = pending.id, status = "error", err = tostring(bytes) }
    return true
  end
  local name = select(2, pcall(function() return file:getFilename() end)) or "dropped"
  injectedCount = injectedCount + 1
  injected[injectedCount] = {
    id = pending.id,
    status = "picked",
    bytes = bytes,
    name = name,
    mime = deliver.mimeFor(name),
  }
  return true
end

--- Drains the backend. Called once per frame by Game:update; a game that builds
--- its own loop must call it too or results never arrive.
--- @param dt number Seconds since the last frame
-- Applies one completed event, whether it came from the backend or from a file
-- dropped on the window. Anything answering a request we have already finished
-- or cancelled is dropped rather than delivered late.
local function handleEvent(event)
  if event.status == "state" then
    -- Not terminal: a platform telling us it is waiting for a tap.
    if pending then state = event.state or state end
    return
  end
  if not pending or event.id ~= pending.id then return end

  if event.status == "cancelled" then
    finish(nil, "cancelled")
  elseif event.status == "error" then
    finish(nil, "error", event.err or "the picker failed")
  elseif event.files then
    local files, failure, total = {}, nil, 0
    for index, file in ipairs(event.files) do
      local one, err = deliver.one(file, pending.options)
      if not one then
        failure = err
        break
      end
      files[index] = one
      total = total + one.size
    end
    if failure then
      warn(failure)
      finish(nil, "error", failure)
    else
      finish({ files = files, size = total }, "picked")
    end
  else
    local one, err = deliver.one(event, pending.options)
    if one then
      finish(one, "picked")
    else
      warn(err)
      finish(nil, "error", err)
    end
  end
end

function filePicker.update(dt)
  local backend = backends.get().filePicker
  backend.tick(dt)
  local startedWith = state

  -- A dropped file answers the pick in flight exactly as a backend result
  -- would, so both go through one handler.
  if injectedCount > 0 then
    local batch, count = injected, injectedCount
    injected, injectedCount = {}, 0
    for i = 1, count do
      handleEvent(batch[i])
    end
  end

  local event = backend.poll()
  while event do
    handleEvent(event)
    event = backend.poll()
  end

  if startedWith ~= state and state == "awaitingGesture" then
    sceneManager.checkAndCallSceneFunction("onFilePickerState", state)
  end
  deliverDeferred()
end

return filePicker

--- macOS, Windows and Linux.
---
--- The file picker shells out to the platform's own dialog — `osascript` on
--- macOS, a Windows Forms `OpenFileDialog` through PowerShell, `zenity` or
--- `kdialog` on Linux — so there is nothing to install and nothing to bundle.
--- Each dialog blocks for as long as the player browses, so it runs in a
--- love.thread (engine/device/threads/pickerThread.lua) and the answer comes
--- back on a channel this module drains once a frame.
---
--- The camera is not implemented here yet, so it falls through to
--- engine/device/backends/null.lua and reports unavailable. It will arrive as a
--- second worker thread reading raw frames from a bundled ffmpeg.
---
--- Known edge: a dialog cannot be closed from code. `cancel` makes the front
--- end stop caring about the answer, and the worker exits on its own once the
--- player dismisses it, but quitting the game with a dialog still open waits
--- for that dismissal.

local system = require "engine.utils.system"
local deliver = require "engine.device.deliver"

local desktop = {}

desktop.name = "desktop"

local RESPONSE_CHANNEL = "spooki.picker.res"
local THREAD_PATH = "engine/device/threads/pickerThread.lua"
local DEFAULT_PROMPT = "Choose a file"

local events, eventCount = {}, 0
local activeThread = nil
local disabled = nil     -- set after a thread error; disables picking for the session

local function warn(message)
  print("[device:desktop] " .. message)
end

local function channel()
  return love.thread.getChannel(RESPONSE_CHANNEL)
end

-- True when `accept` asks for images, which is all the platform dialogs can
-- usefully filter on. Anything more specific shows every file.
local function wantsImages(accept)
  if type(accept) ~= "table" then return false end
  for _, pattern in ipairs(accept) do
    if type(pattern) == "string" and pattern:lower():find("image", 1, true) then
      return true
    end
  end
  return false
end

local function push(event)
  eventCount = eventCount + 1
  events[eventCount] = event
end

desktop.filePicker = {}

--- A dialog is possible wherever love.thread exists, which is every desktop
--- build. Whether the specific helper is installed is only discoverable by
--- running it, so a Linux box with neither zenity nor kdialog reports available
--- here and fails the first pick with a message naming them.
--- @return boolean
function desktop.filePicker.isAvailable()
  if disabled then return false end
  return system.isDesktop() and love.thread ~= nil
end

--- @return table
function desktop.filePicker.getCapabilities()
  return {
    pick = desktop.filePicker.isAvailable(),
    -- One file at a time: the dialogs can do more, but the front end's result
    -- shape for it is not exercised anywhere yet.
    multiple = false,
    acceptFilter = true,
    fromCamera = false,
    -- Desktop dialogs open from code; only browsers need a player's tap.
    needsGesture = false,
    dragDrop = true,
  }
end

--- @param request DevicePickRequest
--- @return boolean ok
--- @return string|nil err
function desktop.filePicker.open(request)
  if not desktop.filePicker.isAvailable() then
    return false, disabled or "no file dialog on this platform"
  end

  -- Stale answers from a pick that was cancelled would otherwise be popped
  -- against the new request's id.
  channel():clear()

  local ok, thread = pcall(love.thread.newThread, THREAD_PATH)
  if not ok or not thread then
    disabled = "could not start the file dialog thread"
    return false, disabled
  end

  local started, err = pcall(function()
    thread:start(request.id, system.getOS(), wantsImages(request.accept), DEFAULT_PROMPT, request.maxBytes)
  end)
  if not started then
    return false, tostring(err)
  end

  activeThread = thread
  return true
end

function desktop.filePicker.cancel()
  -- The dialog belongs to the OS and cannot be dismissed from here. Dropping
  -- the thread and clearing the channel is enough: the front end matches
  -- answers by request id, so whatever the player eventually chooses is
  -- discarded.
  activeThread = nil
  channel():clear()
  events, eventCount = {}, 0
end

--- @param dt number
function desktop.filePicker.tick(dt) -- luacheck: ignore dt
  local message = channel():pop()
  while message do
    if type(message) == "table" then
      if message.ok then
        local name = (message.path or ""):gsub("^.*[/\\]", "")
        push({
          id = message.id,
          status = "picked",
          bytes = message.bytes,
          name = name ~= "" and name or "picked",
          mime = deliver.mimeFor(name),
        })
      elseif message.cancelled then
        push({ id = message.id, status = "cancelled" })
      else
        push({ id = message.id, status = "error", err = message.err or "the file dialog failed" })
      end
      activeThread = nil
    end
    message = channel():pop()
  end
end

--- @return DevicePickEvent|nil
function desktop.filePicker.poll()
  if eventCount == 0 then return nil end
  local event = events[1]
  table.remove(events, 1)
  eventCount = eventCount - 1
  return event
end

function desktop.filePicker.shutdown()
  activeThread = nil
  events, eventCount = {}, 0
  local ok = pcall(function() channel():clear() end)
  if not ok then warn("could not clear the picker channel") end
end

--- Reports a worker that died. Called by the front end from love.threaderror.
--- A dead dialog thread means the request in flight will never be answered, so
--- it is failed here and picking is disabled for the rest of the session rather
--- than hanging forever.
--- @param thread love.Thread The thread that errored
--- @param errorString string The error it died with
--- @return boolean handled Whether this was our thread
function desktop.filePicker.threaderror(thread, errorString)
  if thread ~= activeThread then return false end
  warn("the file dialog thread died: " .. tostring(errorString))
  disabled = "the file dialog thread died: " .. tostring(errorString)
  activeThread = nil
  return true
end

return desktop

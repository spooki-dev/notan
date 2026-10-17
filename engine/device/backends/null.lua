--- The backend contract, and the implementation used when nothing better is
--- available: every capability reports false and every call is a no-op.
---
--- `engine/device/backends.lua` fills any function a real backend leaves out
--- from this table, so a half-finished backend degrades to "unavailable"
--- instead of erroring. Read this file to learn what a backend must provide.
---
--- Division of labour: a backend deals only in bytes and platform mechanics.
--- The front ends (engine/device/filePicker.lua, engine/device/camera.lua) own
--- config validation, the in-flight request, the result queue, the conversion
--- to an Image or a save-directory file, and the callbacks. A backend never
--- calls game code and never raises: it returns `false, err` and reports
--- failures through `poll`.
---
--- Requests carry an `id` and the front end ignores any event whose `id` does
--- not match the request in flight, so a result arriving after a cancel is
--- discarded rather than delivered late.

local null = {}

null.name = "null"

---@class DevicePickRequest
---@field id number Monotonic request id; echoed back in the poll event
---@field deliver string "image", "bytes" or "file" (the front end converts)
---@field accept table|nil MIME patterns or extensions to filter by
---@field multiple boolean Whether more than one file may be returned
---@field maxBytes number Largest acceptable file
---@field source string "files" or "camera"

---@class DevicePickEvent
---@field id number The request this answers
---@field status string "picked", "cancelled", "error" or "state"
---@field bytes string|nil Encoded file contents when status is "picked"
---@field name string|nil File name as the device reported it
---@field mime string|nil MIME type when the platform supplies one
---@field err string|nil Reason when status is "error"
---@field state string|nil For status "state": the new getState() value, e.g.
--- "awaitingGesture" where the platform needs a player tap before it will open
--- the dialog. A "state" event is not terminal and never fires the callback.
---@field files table|nil Array of { bytes, name, mime } for a multiple pick

null.filePicker = {}

--- Whether this platform can show a file picker at all.
--- @return boolean
function null.filePicker.isAvailable()
  return false
end

--- What this platform's picker can do. `needsGesture` is true where the picker
--- must be opened from a user gesture (browsers), which costs the player an
--- extra tap; a game can word its prompt from it.
--- @return table
function null.filePicker.getCapabilities()
  return {
    pick = false, multiple = false, acceptFilter = false,
    fromCamera = false, needsGesture = false, dragDrop = false,
  }
end

--- Starts a pick. Returns immediately; the result arrives through `poll`.
--- @param request DevicePickRequest
--- @return boolean ok
--- @return string|nil err
function null.filePicker.open(request) -- luacheck: ignore request
  return false, "no file picker on this platform"
end

--- Abandons the pick in flight, if any. Must not produce a poll event.
function null.filePicker.cancel()
end

--- Called once per frame before `poll`, so a backend can move work forward:
--- read a thread Channel, check for a file the page wrote, honour a frame rate.
--- @param dt number Seconds since the last frame
function null.filePicker.tick(dt) -- luacheck: ignore dt
end

--- Non-blocking: drains one queued event, or returns nil when none is waiting.
--- The front end calls this until it returns nil, so it must *not* manufacture
--- an event on demand or the drain never ends: produce events in `tick`.
--- @return DevicePickEvent|nil
function null.filePicker.poll()
  return nil
end

--- Releases whatever the backend holds: a worker thread, a stream, a page
--- handle. Called from Game:quit, and again before a backend is re-selected on
--- a hot reload. Must be safe to call when nothing is open.
function null.filePicker.shutdown()
end

--- A worker thread died. Backends that use love.thread claim the ones they own
--- and return true; the front end then fails whatever was in flight, because a
--- dead worker means an answer that will never arrive.
--- @param thread love.Thread The thread that errored
--- @param errorString string The error it died with
--- @return boolean handled Whether this was the backend's thread
function null.filePicker.threaderror(thread, errorString) -- luacheck: ignore thread errorString
  return false
end

---@class DeviceCameraRequest
---@field id number Monotonic request id; echoed back in the poll event
---@field width number Requested preview width
---@field height number Requested preview height
---@field fps number Requested preview frame rate
---@field facing string|nil "front" or "back"
---@field deviceId string|nil A specific device from listDevices

---@class DeviceCameraEvent
---@field id number The request this answers
---@field status string "started", "denied", "error", "frame", "still" or "state"
---@field bytes string|nil Raw RGBA8 for "frame", encoded image for "still"
---@field width number|nil Frame width for "frame"
---@field height number|nil Frame height for "frame"
---@field name string|nil File name for "still"
---@field mime string|nil MIME type for "still"
---@field err string|nil Reason when status is "error"
---@field state string|nil For status "state": the new getState() value. Not
--- terminal; never fires the callback.

null.camera = {}

--- Whether this platform can open a camera at all.
--- @return boolean
function null.camera.isAvailable()
  return false
end

--- What this platform's camera can do.
--- @return table
function null.camera.getCapabilities()
  return { preview = false, capture = false, facingSwitch = false, needsGesture = false }
end

--- The cameras this platform can see. Empty when there are none or the
--- platform cannot enumerate them.
--- @return table Array of { id = string, name = string, facing = string|nil }
function null.camera.listDevices()
  return {}
end

--- Opens the camera. Returns immediately; "started" or "denied" arrives
--- through `poll`, then one "frame" event per captured frame.
--- @param request DeviceCameraRequest
--- @return boolean ok
--- @return string|nil err
function null.camera.start(request) -- luacheck: ignore request
  return false, "no camera on this platform"
end

--- Closes the camera and stops producing frames. Must not produce a poll event.
function null.camera.stop()
end

--- Requests one still at the best resolution the device offers. The result
--- arrives through `poll` as a "still" event.
--- @param request DeviceCameraRequest
--- @return boolean ok
--- @return string|nil err
function null.camera.capture(request) -- luacheck: ignore request
  return false, "no camera on this platform"
end

--- Called once per frame before `poll`. This is where a backend reads its
--- Channel or its frame file and queues at most one "frame" event, dropping any
--- older frame it had not handed over yet: the game must never fall behind the
--- camera, and a stale frame is worth less than the newest one.
--- @param dt number Seconds since the last frame
function null.camera.tick(dt) -- luacheck: ignore dt
end

--- Non-blocking: drains one queued event, or returns nil when none is waiting.
--- As with the picker, never manufacture an event here: the front end polls
--- until nil.
--- @return DeviceCameraEvent|nil
function null.camera.poll()
  return nil
end

--- Releases whatever the backend holds. See filePicker.shutdown.
function null.camera.shutdown()
end

--- A worker thread died. See filePicker.threaderror.
--- @param thread love.Thread The thread that errored
--- @param errorString string The error it died with
--- @return boolean handled
function null.camera.threaderror(thread, errorString) -- luacheck: ignore thread errorString
  return false
end

return null

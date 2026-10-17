--- The Lua half of the page bridge used by engine/device/backends/web.lua.
---
--- love.js exposes no `js` module, no `ccall` and no `FS`, so neither direction
--- of this channel is built from an API meant for it. Both halves are built
--- from what the compat runtime does export, and the page half lives in
--- scripts/web/index.html.
---
--- **Lua to JS** is a character device. The page registers `/dev/spooki` with
--- `Module.FS_createDevice`, whose write callback runs in JS once per byte, and
--- Lua writes newline-terminated commands to it with plain `io`. (`"w"` is safe
--- on a device: emscripten's `FS.open` strips `O_TRUNC` for character devices,
--- so there is no truncate to fail.) If that device cannot be created — a
--- future love.js dropping the export — the page instead sniffs `Module.print`,
--- and this module falls back to a prefixed `print`. `main.lua` already sets
--- `io.stdout:setvbuf("no")`, so the fallback has no buffering delay.
---
--- **JS to Lua** is files in `/tmp/spooki/`, written with
--- `Module.FS_createDataFile` and read here with plain `io`. They live in `/tmp`
--- and not in the save directory on purpose: the save directory is the IDBFS
--- mount, and the page's existing ten-second `flushSaves` would copy every
--- camera frame into IndexedDB.
---
--- | File | Holds |
--- |---|---|
--- | `events` | one `key=value` line per event, newest last, each with a `seq` |
--- | `cam.hdr` | `seq width height` — tiny, so the per-frame poll is nearly free |
--- | `cam.rgba` | the newest frame as raw RGBA8, read only when `seq` changed |
--- | `blob-<id>.bin` | a picked file or a captured still |
--- | `window` | `width height` — the size the frame wants the window to be |
---
--- Values are percent-escaped, so a file name with a space or a newline
--- survives the line framing. There is no JSON: the only serialiser in the tree
--- is dev-only and `engine/` may not require it.

local webBridge = {}

local DIR = "/tmp/spooki/"
local DEVICE = "/dev/spooki"
local PRINT_PREFIX = "\1spooki "

local device = nil
local deviceChecked = false
local lastEventSeq = 0
local lastFrameSeq = -1

local function warn(message)
  print("[device:web] " .. message)
end

--- Percent-escapes a value so it survives the space-separated line framing.
--- @param value any Converted with tostring
--- @return string
function webBridge.encode(value)
  return (tostring(value):gsub("[^%w%.%-_]", function(char)
    return string.format("%%%02X", string.byte(char))
  end))
end

--- Reverses `encode`.
--- @param value string
--- @return string
function webBridge.decode(value)
  return (tostring(value):gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

local function openDevice()
  if deviceChecked then return device end
  deviceChecked = true
  local ok, handle = pcall(io.open, DEVICE, "w")
  if ok and handle then
    pcall(function() handle:setvbuf("no") end)
    device = handle
  else
    warn("no " .. DEVICE .. "; falling back to the print channel")
  end
  return device
end

--- Sends one command to the page. Falls back to a prefixed `print` when the
--- character device is unavailable, which the page sniffs.
--- @param command string Command name
--- @param fields table|nil Key/value pairs; values are escaped
function webBridge.send(command, fields)
  local parts = { command }
  if fields then
    -- Sorted so a command is byte-identical run to run, which makes the page's
    -- console log readable and a test's expectations stable.
    local keys = {}
    for key in pairs(fields) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
      parts[#parts + 1] = key .. "=" .. webBridge.encode(fields[key])
    end
  end
  local line = table.concat(parts, " ")

  local handle = openDevice()
  if handle then
    local ok = pcall(function()
      handle:write(line .. "\n")
      handle:flush()
    end)
    if ok then return end
    warn("the device channel failed; falling back to print")
    device, deviceChecked = nil, true
  end
  print(PRINT_PREFIX .. line)
end

local function readAll(path)
  local ok, handle = pcall(io.open, path, "rb")
  if not ok or not handle then return nil end
  local contents = handle:read("*a")
  handle:close()
  return contents
end

local function parseLine(line)
  local event = {}
  for key, value in line:gmatch("([%w_]+)=([^%s]*)") do
    event[key] = webBridge.decode(value)
  end
  return event
end

--- Reads whatever the page has posted since the last call.
---
--- The page rewrites the file in place and keeps only the most recent lines, so
--- events are identified by a monotonic `seq` rather than by position: anything
--- at or below the last one seen has already been handled.
--- @return table Array of event tables, oldest first
function webBridge.readEvents()
  local contents = readAll(DIR .. "events")
  if not contents or contents == "" then return {} end
  local events = {}
  for line in contents:gmatch("[^\n]+") do
    local event = parseLine(line)
    local seq = tonumber(event.seq)
    if seq and seq > lastEventSeq then
      events[#events + 1] = event
    end
  end
  -- Bump only after the whole file parsed, so a half-written file is re-read
  -- rather than skipped.
  for _, event in ipairs(events) do
    local seq = tonumber(event.seq)
    if seq and seq > lastEventSeq then lastEventSeq = seq end
  end
  return events
end

--- Reads the newest camera frame, if there is one that has not been read.
---
--- The sixteen-byte header is checked first so an unchanged frame costs one
--- tiny read rather than a copy of the whole buffer.
--- @return string|nil bytes Raw RGBA8, nil when there is nothing new
--- @return number|nil width
--- @return number|nil height
function webBridge.readFrame()
  local header = readAll(DIR .. "cam.hdr")
  if not header then return nil end
  local seq, width, height = header:match("^(%d+)%s+(%d+)%s+(%d+)")
  if not seq then return nil end
  seq = tonumber(seq)
  if seq == lastFrameSeq then return nil end
  local bytes = readAll(DIR .. "cam.rgba")
  if not bytes then return nil end
  lastFrameSeq = seq
  return bytes, tonumber(width), tonumber(height)
end

--- Reads one blob the page wrote (a picked file or a captured still).
--- @param name string Blob file name as the event reported it
--- @return string|nil bytes
function webBridge.readBlob(name)
  if type(name) ~= "string" or name == "" or name:find("[/\\]") then return nil end
  return readAll(DIR .. name)
end

--- The size the page wants the window to be, if it has asked for one.
---
--- Deliberately not part of the handshake: a page may track its frame without
--- offering a picker or a camera, and `isAvailable` must keep answering for
--- those alone. See engine/device/webWindow.lua for what is done with it.
--- @return number|nil width
--- @return number|nil height
function webBridge.readWindowSize()
  local contents = readAll(DIR .. "window")
  if not contents then return nil end
  local width, height = contents:match("^(%d+)%s+(%d+)")
  if not width then return nil end
  return tonumber(width), tonumber(height)
end

--- Whether the page bridge answered. The page writes `events` as soon as it has
--- attached, so the file existing is the handshake.
--- @return boolean
function webBridge.isAvailable()
  return readAll(DIR .. "events") ~= nil
end

--- Forgets the sequence counters. Called when a backend is re-selected, so a
--- hot reload does not treat already-handled events as new or skip new ones.
function webBridge.reset()
  lastEventSeq = 0
  lastFrameSeq = -1
end

return webBridge

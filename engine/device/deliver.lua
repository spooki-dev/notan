--- Turns the bytes a device backend produced into the shape the game asked for.
---
--- Shared by engine/device/filePicker.lua and engine/device/camera.lua because
--- a picked file and a captured still are the same problem: some encoded image
--- bytes plus a name, to be handed over as a drawable Image, as the raw bytes,
--- or as a file in the save directory.
---
--- Names come from the device, so they are never trusted as paths: `safeName`
--- strips any directory part and anything that is not a plain file-name
--- character before a write.

local decode = require "engine.device.decode"

local deliver = {}

-- Enough to label what a game is realistically asked to import. A platform that
-- reports its own MIME type is always believed over this guess.
local MIME_BY_EXTENSION = {
  png = "image/png", jpg = "image/jpeg", jpeg = "image/jpeg", gif = "image/gif",
  bmp = "image/bmp", tga = "image/x-tga", webp = "image/webp", hdr = "image/vnd.radiance",
  json = "application/json", txt = "text/plain", lua = "text/x-lua", csv = "text/csv",
  ogg = "audio/ogg", wav = "audio/wav", mp3 = "audio/mpeg", flac = "audio/flac",
}

--- Guesses a MIME type from a file name's extension.
--- @param name string|nil File name
--- @return string|nil mime nil when the extension is unknown
function deliver.mimeFor(name)
  if type(name) ~= "string" then return nil end
  local extension = name:match("%.([%a%d]+)$")
  if not extension then return nil end
  return MIME_BY_EXTENSION[extension:lower()]
end

--- Reduces a device-supplied name to a safe, bare file name.
--- @param name string|nil The name the device reported
--- @return string A name with no directory part and no path metacharacters
function deliver.safeName(name)
  local base = tostring(name or "picked"):gsub("^.*[/\\]", "")
  base = base:gsub("[^%w%.%-_]", "_")
  if base == "" or base == "." then base = "picked" end
  return base
end

---@class DeliverOptions
---@field deliver string "image", "bytes" or "file"
---@field maxBytes number Largest acceptable size in bytes
---@field saveAs string|nil Override the file name for deliver = "file"
---@field saveDir string|nil Save-directory folder for deliver = "file"

--- Converts one `{ bytes, name, mime }` into a DevicePickResult.
--- @param file table { bytes = string, name = string|nil, mime = string|nil }
--- @param opts DeliverOptions
--- @return DevicePickResult|nil result nil on failure
--- @return string|nil err Reason when result is nil
function deliver.one(file, opts)
  local bytes = file.bytes
  if type(bytes) ~= "string" or bytes == "" then
    return nil, "the file was empty"
  end
  if opts.maxBytes and #bytes > opts.maxBytes then
    return nil, string.format("the file is %d bytes, over the %d byte limit", #bytes, opts.maxBytes)
  end

  local name = deliver.safeName(file.name)
  local result = { name = name, mime = file.mime, size = #bytes }

  if opts.deliver == "bytes" then
    result.bytes = bytes
    return result
  end

  if opts.deliver == "file" then
    local path = opts.saveAs and deliver.safeName(opts.saveAs) or name
    if opts.saveDir and opts.saveDir ~= "" then
      if not pcall(love.filesystem.createDirectory, opts.saveDir) then
        return nil, "could not create " .. opts.saveDir .. " in the save directory"
      end
      path = opts.saveDir .. "/" .. path
    end
    local ok, writeErr = pcall(love.filesystem.write, path, bytes)
    if not ok then
      return nil, "could not write " .. path .. ": " .. tostring(writeErr)
    end
    result.path = path
    return result
  end

  local image, err = decode.imageFromBytes(bytes, name)
  if not image then
    return nil, "could not decode " .. name .. ": " .. tostring(err)
  end
  result.image = image
  result.width = image:getWidth()
  result.height = image:getHeight()
  return result
end

return deliver

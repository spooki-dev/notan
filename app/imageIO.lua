--- Reading and writing images anywhere on disk.
---
--- LOVE's own filesystem is sandboxed to the game folder and the save
--- directory, which is no use for an app that opens the user's pictures. So
--- files come in as bytes read with plain Lua `io` and are handed to
--- `love.image` as FileData; files go out the same way.
---
--- Choosing the file is not this module's job: `engine/device/filePicker.lua`
--- shows the device's own picker on every platform and hands back bytes. This
--- module turns bytes into an ImageData (`decode`), reads a path for itself
--- when there is one to read (a drop, or the command line), and writes PNGs.
local imageIO = {}

--- Everything before the last path separator.
---@param path string
---@return string
function imageIO.dirname(path)
  return path:match("^(.*)[/\\][^/\\]*$") or "."
end

--- The file name without its directory.
---@param path string
---@return string
function imageIO.basename(path)
  return path:match("[^/\\]+$") or path
end

--- The file name without its directory or extension.
---@param path string
---@return string
function imageIO.stem(path)
  local base = imageIO.basename(path)
  return base:match("^(.*)%.[^.]+$") or base
end

--- Loads an image from an absolute path on disk.
---@param path string
---@return love.ImageData|nil imageData
---@return string|nil error
function imageIO.load(path)
  local file, openErr = io.open(path, "rb")
  if not file then
    return nil, "could not open " .. imageIO.basename(path) .. ": " .. tostring(openErr)
  end
  local bytes = file:read("*a")
  file:close()
  return imageIO.decode(bytes, imageIO.basename(path))
end

--- Turns the bytes of an image file into ImageData. Used for files read off
--- disk and for the bytes the device file picker hands back, which have a
--- name but no path.
---@param bytes string|nil The whole file
---@param name string|nil File name, used to pick the decoder
---@return love.ImageData|nil imageData
---@return string|nil error
function imageIO.decode(bytes, name)
  name = name or "image"
  if not bytes or #bytes == 0 then
    return nil, name .. " is empty"
  end

  -- The name matters: love.image picks its decoder from the extension.
  local ok, fileData = pcall(love.filesystem.newFileData, bytes, name)
  if not ok then
    return nil, "could not read " .. name
  end
  local decoded, imageData = pcall(love.image.newImageData, fileData)
  if not decoded then
    return nil, name .. " is not an image LOVE can decode"
  end
  return imageData
end

--- Loads an image from a file dragged onto the window.
---@param file love.File LOVE's DroppedFile
---@return love.ImageData|nil imageData
---@return string|nil error
---@return string|nil path Absolute path of the dropped file
function imageIO.loadDropped(file)
  local path = file.getFilename and file:getFilename() or nil
  if path then
    local imageData, err = imageIO.load(path)
    if imageData then return imageData, nil, path end
    return nil, err, path
  end

  -- No path (shouldn't happen on desktop): fall back to LOVE's own handle.
  local opened = pcall(file.open, file, "r")
  if not opened then return nil, "could not open the dropped file", nil end
  local ok, imageData = pcall(love.image.newImageData, file)
  file:close()
  if not ok then return nil, "that file is not an image LOVE can decode", nil end
  return imageData, nil, nil
end

--- Writes ImageData to a PNG anywhere on disk.
---@param imageData love.ImageData
---@param path string Absolute destination path
---@return boolean ok
---@return string|nil error
function imageIO.savePng(imageData, path)
  local ok, encoded = pcall(imageData.encode, imageData, "png")
  if not ok then
    return false, "could not encode the image"
  end
  local file, openErr = io.open(path, "wb")
  if not file then
    return false, "could not write " .. imageIO.basename(path) .. ": " .. tostring(openErr)
  end
  file:write(encoded:getString())
  file:close()
  return true
end

return imageIO

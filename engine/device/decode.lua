--- Byte-to-texture helpers shared by every device backend.
---
--- Backends deal only in bytes: a picked file or a still arrives as encoded
--- image data (PNG, JPEG, ...), a camera preview frame arrives as raw RGBA8.
--- This module turns both into LÖVE objects and is the only place that knows
--- how. Every call is wrapped so malformed data from a device or a browser
--- returns `nil, err` instead of raising.

local decode = {}

--- Decodes encoded image bytes into an ImageData.
--- @param bytes string Encoded file contents
--- @param name string|nil File name; LÖVE picks its decoder from the extension
--- @return love.ImageData|nil imageData nil on failure
--- @return string|nil err Reason when imageData is nil
function decode.imageDataFromBytes(bytes, name)
  if type(bytes) ~= "string" or bytes == "" then
    return nil, "no image data"
  end
  local ok, result = pcall(function()
    local fileData = love.filesystem.newFileData(bytes, name or "picked.png")
    return love.image.newImageData(fileData)
  end)
  if not ok then
    return nil, tostring(result)
  end
  return result
end

--- Decodes encoded image bytes into a drawable Image. The intermediate
--- ImageData is released immediately; games that need pixel access should ask
--- for `deliver = "bytes"` instead.
--- @param bytes string Encoded file contents
--- @param name string|nil File name; LÖVE picks its decoder from the extension
--- @return love.Image|nil image nil on failure
--- @return string|nil err Reason when image is nil
function decode.imageFromBytes(bytes, name)
  local imageData, err = decode.imageDataFromBytes(bytes, name)
  if not imageData then
    return nil, err
  end
  local ok, result = pcall(love.graphics.newImage, imageData)
  imageData:release()
  if not ok then
    return nil, tostring(result)
  end
  return result
end

--- Wraps raw RGBA8 pixels in an ImageData. Used for camera preview frames,
--- which are never encoded: encoding and decoding a PNG per frame would cost
--- far more than the copy.
--- @param bytes string Exactly width * height * 4 bytes, row-major RGBA8
--- @param width number Frame width in pixels
--- @param height number Frame height in pixels
--- @return love.ImageData|nil imageData nil on failure
--- @return string|nil err Reason when imageData is nil
function decode.imageDataFromRGBA(bytes, width, height)
  if type(bytes) ~= "string" then
    return nil, "no pixel data"
  end
  local expected = width * height * 4
  if #bytes ~= expected then
    return nil, string.format("expected %d bytes for %dx%d, got %d", expected, width, height, #bytes)
  end
  local ok, result = pcall(love.image.newImageData, width, height, "rgba8", bytes)
  if not ok then
    return nil, tostring(result)
  end
  return result
end

--- Uploads an ImageData into an existing Image, creating the Image on the first
--- call. One Image is reused for the whole life of a camera stream so a running
--- preview allocates no GPU texture per frame.
--- @param image love.Image|nil The Image to update, or nil to create one
--- @param imageData love.ImageData Pixels to upload
--- @return love.Image|nil image The same Image, or a new one, or nil on failure
--- @return string|nil err Reason when image is nil
function decode.uploadToImage(image, imageData)
  if not image then
    local ok, created = pcall(love.graphics.newImage, imageData)
    if not ok then
      return nil, tostring(created)
    end
    return created
  end
  local ok, err = pcall(function()
    image:replacePixels(imageData)
  end)
  if not ok then
    return nil, tostring(err)
  end
  return image
end

return decode

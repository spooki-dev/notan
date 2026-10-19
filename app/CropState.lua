local Object = require "engine.lib.classic"

--- The crop box: a rectangle locked to the ratio of the surface you are
--- actually painting on.
---
--- Two separate things live here, on purpose. The *canvas dimensions* are a
--- property of the painter -- a 16x20 panel stays 16x20 whatever photo is
--- open -- so they are saved between sessions like any other preference. The
--- *box* is a property of the photo, so it is thrown away and re-centred
--- whenever a new image is adopted. Only the ratio of the dimensions is ever
--- used, which is why no unit is named anywhere: inches, centimetres and
--- pixels all crop the same.
---
--- The rectangle is kept in working-image pixels (`Pipeline.width/height`
--- space, not the source's), integer-valued, so it can size an export canvas
--- directly and so the view transform can map it to the screen with the same
--- `screen = offset + image * zoom` the rest of the viewer uses.
---
--- It exposes `getState`/`setValue`/`setEnabled`/`isEnabled` and a `defs`
--- list, which is the whole of the interface `gameObjects/ControlPanel.lua`
--- needs. That is deliberate: the panel treats this and the effect Pipeline as
--- interchangeable providers rather than carrying a special case for the crop.
---@class CropState : Object
---@field defs table[] Panel row definitions, shaped like an EffectDef
---@field rect table The box as { x, y, w, h } in working-image pixels
---@field imageWidth number Working image width, 0 before anything is open
---@field imageHeight number Working image height, 0 before anything is open
local CropState = Object:extend()

--- Smallest edge the box may be dragged down to, in working-image pixels.
--- Small enough to crop in hard on a detail, large enough that the box cannot
--- be lost under its own corner handles.
local MIN_EDGE = 32
--- Bounds on a typed dimension. The upper one is only there to stop a slipped
--- keypress turning the ratio into something unreadable.
local MIN_DIM, MAX_DIM = 1, 9999

--- Greatest common divisor, for showing 16x20 as the 4:5 it really is.
---@param a number
---@param b number
---@return number
local function gcd(a, b)
  while b > 0 do
    a, b = b, a % b
  end
  return a
end

---@param x number
---@param low number
---@param high number
---@return number
local function clamp(x, low, high)
  if x < low then return low end
  if x > high then return high end
  return x
end

function CropState:new()
  self.imageWidth, self.imageHeight = 0, 0
  self.rect = { x = 0, y = 0, w = 0, h = 0 }

  self.state = {
    crop = { enabled = false, values = { width = 16, height = 20 } },
  }

  local crop = self
  self.defs = {
    {
      id = "crop",
      label = "Crop to canvas",
      hint = "The panel you are painting on -- only the ratio matters. "
        .. "Drag the box to move it, a corner to resize.",
      params = {
        { key = "width",  label = "Canvas width",  kind = "field", min = MIN_DIM, max = MAX_DIM, default = 16, format = "%d" },
        { key = "height", label = "Canvas height", kind = "field", min = MIN_DIM, max = MAX_DIM, default = 20, format = "%d" },
        {
          kind = "readout",
          label = "Crop",
          ---@return string
          text = function() return crop:summary() end,
        },
        {
          kind = "button",
          label = "Reset box",
          action = function() crop:resetBox() end,
        },
      },
    },
  }
end

-- Panel provider interface ---------------------------------------------------

--- The per-row state table the control panel reads and writes.
---@param id string
---@return table|nil
function CropState:getState(id)
  return self.state[id]
end

--- Whether the crop is switched on. False before an image is open, whatever
--- the checkbox says: there is nothing to crop.
---@param id string
---@return boolean
function CropState:isEnabled(id)
  local state = self.state[id]
  return state ~= nil and state.enabled
end

--- Turns the crop on or off.
---@param id string
---@param enabled boolean
function CropState:setEnabled(id, enabled)
  local state = self.state[id]
  if not state or state.enabled == enabled then return end
  state.enabled = enabled
end

--- Sets a typed dimension and reshapes the box to the new ratio.
---
--- How tightly you are cropped is measured *before* the ratio changes,
--- because the two dimensions are entered one at a time and the ratio
--- between the first keystroke and the second is a shape nobody asked for.
--- Measuring first means a 16x20 panel retyped as 3x2 passes through 3x20
--- without the box ever being squeezed down to the sliver that shape implies.
---@param id string
---@param key string
---@param value number
function CropState:setValue(id, key, value)
  local state = self.state[id]
  if not state then return end
  value = math.floor(clamp(value, MIN_DIM, MAX_DIM) + 0.5)
  if state.values[key] == value then return end
  local coverage = self:coverage()
  state.values[key] = value
  self:refitToRatio(coverage)
end

-- Geometry -------------------------------------------------------------------

--- Width over height of the entered dimensions.
---@return number
function CropState:ratio()
  local values = self.state.crop.values
  return values.width / values.height
end

--- Whether there is an image to crop and the crop is switched on.
---@return boolean
function CropState:isActive()
  return self.state.crop.enabled and self.imageWidth > 0 and self.imageHeight > 0
end

--- The box, or nil when there is nothing to show one over.
---
--- The table is reused rather than rebuilt, so a caller drawing every frame
--- allocates nothing -- which also means callers must read it, never edit it.
---@return table|nil rect { x, y, w, h } in working-image pixels
function CropState:getRect()
  if not self:isActive() then return nil end
  return self.rect
end

--- Points the crop at a newly opened image and re-centres the box. The box
--- belongs to the photo, so a new photo always gets a fresh one.
---@param width number Working image width
---@param height number Working image height
function CropState:setImageSize(width, height)
  self.imageWidth, self.imageHeight = width, height
  self:resetBox()
end

--- Puts the box back to the largest rectangle of the current ratio that fits,
--- centred on the image.
function CropState:resetBox()
  local iw, ih = self.imageWidth, self.imageHeight
  if iw <= 0 or ih <= 0 then
    self.rect.x, self.rect.y, self.rect.w, self.rect.h = 0, 0, 0, 0
    return
  end
  local w, h = self:largestFit()
  self.rect.w, self.rect.h = w, h
  self.rect.x = math.floor((iw - w) / 2 + 0.5)
  self.rect.y = math.floor((ih - h) / 2 + 0.5)
end

--- The biggest box of the current ratio the image can hold.
---@return number width
---@return number height
function CropState:largestFit()
  local iw, ih = self.imageWidth, self.imageHeight
  local ratio = self:ratio()
  local w, h = iw, iw / ratio
  if h > ih then
    w, h = ih * ratio, ih
  end
  return math.max(1, math.floor(w)), math.max(1, math.floor(h))
end

--- How tight the crop is, as a fraction of the biggest box this ratio could
--- have. 1 means the box is as large as the image allows.
---
--- This, rather than the box's width or its area, is what survives a change
--- of ratio: "I am cropped in about halfway" is a decision about the photo,
--- where "my box is 2457 wide" is an accident of the shape it had at the time.
---@return number
function CropState:coverage()
  if self.imageWidth <= 0 or self.rect.w <= 0 then return 1 end
  local maxW = select(1, self:largestFit())
  return clamp(self.rect.w / maxW, 0, 1)
end

--- Reshapes the box to the current ratio, keeping its centre and how tightly
--- it is cropped.
---
--- Correcting a typo in one field should not throw away the framing you just
--- chose, which is why this scales rather than resetting.
---@param coverage number Fraction of the largest fitting box to occupy, 0..1
function CropState:refitToRatio(coverage)
  if self.imageWidth <= 0 or self.imageHeight <= 0 then return end
  if self.rect.w <= 0 then
    self:resetBox()
    return
  end

  local centreX = self.rect.x + self.rect.w / 2
  local centreY = self.rect.y + self.rect.h / 2
  local maxW, maxH = self:largestFit()
  local w, h = maxW * coverage, maxH * coverage

  local minW, minH = self:minimumSize()
  if w < minW then w, h = minW, minH end

  self.rect.w = math.max(1, math.floor(w + 0.5))
  self.rect.h = math.max(1, math.floor(h + 0.5))
  self.rect.x = math.floor(centreX - self.rect.w / 2 + 0.5)
  self.rect.y = math.floor(centreY - self.rect.h / 2 + 0.5)
  self:clampIntoImage()
end

--- The smallest box of the current ratio, never larger than the image itself.
---@return number width
---@return number height
function CropState:minimumSize()
  local ratio = self:ratio()
  local w, h = MIN_EDGE, MIN_EDGE
  if ratio >= 1 then w = MIN_EDGE * ratio else h = MIN_EDGE / ratio end
  local maxW, maxH = self:largestFit()
  local scale = math.min(1, maxW / w, maxH / h)
  return w * scale, h * scale
end

--- Slides the box back inside the image without changing its size.
function CropState:clampIntoImage()
  self.rect.x = math.floor(clamp(self.rect.x, 0, math.max(0, self.imageWidth - self.rect.w)))
  self.rect.y = math.floor(clamp(self.rect.y, 0, math.max(0, self.imageHeight - self.rect.h)))
end

--- Whether a point in working-image pixels is inside the box.
---@param imageX number
---@param imageY number
---@return boolean
function CropState:contains(imageX, imageY)
  return imageX >= self.rect.x and imageX < self.rect.x + self.rect.w
    and imageY >= self.rect.y and imageY < self.rect.y + self.rect.h
end

--- Moves the box to an absolute position, clamped to the image.
---@param x number Left edge in working-image pixels
---@param y number Top edge in working-image pixels
function CropState:moveTo(x, y)
  self.rect.x, self.rect.y = math.floor(x + 0.5), math.floor(y + 0.5)
  self:clampIntoImage()
end

--- Corner opposite the handle being dragged, which stays put while the box
--- resizes, and the direction the box grows in from it.
---@param handle string One of "tl", "tr", "bl", "br"
---@param rect table The box the drag started from
---@return number anchorX
---@return number anchorY
---@return number dirX -1 when the box extends left of the anchor, else 1
---@return number dirY -1 when the box extends above the anchor, else 1
local function anchorFor(handle, rect)
  local right, bottom = rect.x + rect.w, rect.y + rect.h
  if handle == "tl" then return right, bottom, -1, -1 end
  if handle == "tr" then return rect.x, bottom, 1, -1 end
  if handle == "bl" then return right, rect.y, -1, 1 end
  return rect.x, rect.y, 1, 1
end

--- Resizes the box by dragging one corner, holding the ratio and the opposite
--- corner fixed.
---
--- The pointer rarely lands on the ratio exactly, so the larger of the two
--- dimensions it asks for wins and the other follows: the box tracks the
--- furthest the pointer has pulled rather than stalling on whichever axis
--- happens to be short.
---@param handle string One of "tl", "tr", "bl", "br"
---@param startRect table The box as it was when the drag began
---@param imageX number Pointer x in working-image pixels
---@param imageY number Pointer y in working-image pixels
function CropState:resizeFrom(handle, startRect, imageX, imageY)
  local anchorX, anchorY, dirX, dirY = anchorFor(handle, startRect)
  local roomX = dirX > 0 and (self.imageWidth - anchorX) or anchorX
  local roomY = dirY > 0 and (self.imageHeight - anchorY) or anchorY

  local wantW = math.max(0, (imageX - anchorX) * dirX)
  local wantH = math.max(0, (imageY - anchorY) * dirY)

  local ratio = self:ratio()
  local w = math.max(wantW, wantH * ratio)
  local h = w / ratio

  local fit = math.min(1, roomX / math.max(w, 0.0001), roomY / math.max(h, 0.0001))
  w, h = w * fit, h * fit

  local minW, minH = self:minimumSize()
  if w < minW then w, h = minW, minH end

  w = math.max(1, math.floor(w + 0.5))
  h = math.max(1, math.floor(h + 0.5))
  self.rect.w, self.rect.h = w, h
  self.rect.x = math.floor(dirX > 0 and anchorX or (anchorX - w))
  self.rect.y = math.floor(dirY > 0 and anchorY or (anchorY - h))
  self:clampIntoImage()
end

-- Display --------------------------------------------------------------------

--- The entered dimensions in lowest terms, e.g. "4:5" for a 16x20 panel.
---@return string
function CropState:ratioText()
  local values = self.state.crop.values
  local divisor = gcd(values.width, values.height)
  if divisor < 1 then divisor = 1 end
  return math.floor(values.width / divisor) .. ":" .. math.floor(values.height / divisor)
end

--- One line for the panel: the ratio, and the pixels the export will be.
---@return string
function CropState:summary()
  if self.imageWidth <= 0 then return self:ratioText() end
  return self:ratioText() .. "  " .. self.rect.w .. "x" .. self.rect.h .. " px"
end

return CropState

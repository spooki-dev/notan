local colors = require "constants.colors"

--- Draws the crop box over an image rectangle.
---
--- An overlay in the same sense as `app/grid.lua`: it draws in whatever
--- coordinate space the caller is in rather than running through the shader
--- chain, so `scenes/Viewer.lua` can put it in screen space with handles that
--- stay a thumb's width at any zoom. Unlike the grid it is never burnt into
--- the export -- the export *is* the box, so drawing its own outline into it
--- would be drawing the frame onto the painting.
---
--- Everything outside the box is dimmed rather than hidden. A painter choosing
--- a crop is choosing what to leave out, and that decision needs the rest of
--- the photo still readable beside it.
local cropOverlay = {}

--- Side of a drawn corner handle, in screen pixels.
cropOverlay.HANDLE = 10
--- How close the pointer must come to a corner to grab its handle. Larger than
--- the handle itself because a fingertip is wider than a cursor, and missing
--- the corner pans the view instead, which is a jarring thing to do by mistake.
cropOverlay.TOUCH = 22

--- How dark the masked-off part of the photo goes. Enough to read the box at a
--- glance, not so much that what you are cropping away becomes unjudgeable.
local MASK_ALPHA = 0.55

--- Draws the dimmed surround, the box outline and its corner handles.
---
--- Both rectangles are in the caller's coordinate space: on screen that is the
--- image's drawn rect and the box within it, already multiplied by the zoom.
---@param x number Left edge of the image
---@param y number Top edge of the image
---@param w number Width of the image
---@param h number Height of the image
---@param boxX number Left edge of the crop box
---@param boxY number Top edge of the crop box
---@param boxW number Width of the crop box
---@param boxH number Height of the crop box
---@param handleSize number|nil Side of a corner handle; 0 or nil draws none
function cropOverlay.draw(x, y, w, h, boxX, boxY, boxW, boxH, handleSize)
  love.graphics.push("all")
  love.graphics.setBlendMode("alpha")

  -- Four bands rather than a stencil: the box is always a rectangle inside a
  -- rectangle, and four fills cost less than a stencil pass every frame.
  love.graphics.setColor(0, 0, 0, MASK_ALPHA)
  love.graphics.rectangle("fill", x, y, w, boxY - y)
  love.graphics.rectangle("fill", x, boxY + boxH, w, (y + h) - (boxY + boxH))
  love.graphics.rectangle("fill", x, boxY, boxX - x, boxH)
  love.graphics.rectangle("fill", boxX + boxW, boxY, (x + w) - (boxX + boxW), boxH)

  -- A dark line under a light one, the same trick the grid uses: a single flat
  -- colour disappears into either a dark or a light photo.
  love.graphics.setLineWidth(1)
  love.graphics.setColor(0, 0, 0, 0.5)
  love.graphics.rectangle("line", boxX + 1.5, boxY + 1.5, boxW - 1, boxH - 1)
  love.graphics.setColor(colors.yellow[1], colors.yellow[2], colors.yellow[3], 0.9)
  love.graphics.rectangle("line", boxX + 0.5, boxY + 0.5, boxW - 1, boxH - 1)

  local s = handleSize or 0
  if s > 0 then
    -- Handles sit inside the box so they never cover the photo outside it, and
    -- so a box pushed against the image edge keeps all four grabbable.
    local half = s / 2
    local cx = { boxX + half, boxX + boxW - half }
    local cy = { boxY + half, boxY + boxH - half }
    for i = 1, 2 do
      for j = 1, 2 do
        love.graphics.setColor(0, 0, 0, 0.5)
        love.graphics.rectangle("fill", cx[i] - half + 1, cy[j] - half + 1, s, s, 2, 2)
        love.graphics.setColor(colors.yellow[1], colors.yellow[2], colors.yellow[3], 1)
        love.graphics.rectangle("fill", cx[i] - half, cy[j] - half, s, s, 2, 2)
      end
    end
  end

  love.graphics.pop()
end

--- Which corner handle a point is grabbing, if any.
---
--- Corners are tested in a fixed order, so a box squashed small enough for two
--- handles to overlap always resolves the same way instead of flickering
--- between them as the pointer moves.
---@param boxX number Left edge of the crop box
---@param boxY number Top edge of the crop box
---@param boxW number Width of the crop box
---@param boxH number Height of the crop box
---@param px number Pointer x, same space as the box
---@param py number Pointer y, same space as the box
---@param radius number|nil How close counts as a grab; defaults to TOUCH
---@return string|nil handle One of "tl", "tr", "bl", "br"
function cropOverlay.handleAt(boxX, boxY, boxW, boxH, px, py, radius)
  local r = radius or cropOverlay.TOUCH
  local right, bottom = boxX + boxW, boxY + boxH
  if math.abs(px - boxX) <= r and math.abs(py - boxY) <= r then return "tl" end
  if math.abs(px - right) <= r and math.abs(py - boxY) <= r then return "tr" end
  if math.abs(px - boxX) <= r and math.abs(py - bottom) <= r then return "bl" end
  if math.abs(px - right) <= r and math.abs(py - bottom) <= r then return "br" end
  return nil
end

return cropOverlay

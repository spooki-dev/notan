--- Draws the composition grid over an image rectangle.
---
--- The grid is an overlay, not an effect: it is drawn in whatever coordinate
--- space the caller is in rather than being run through the shader chain, so
--- `scenes/Viewer.lua` can draw it in screen space (one-pixel lines that stay
--- crisp at any zoom, and that stay visible while the original is held) and
--- burn it into the export at image scale with the same code.
---
--- Lines divide the rectangle evenly: `n` lines make `n + 1` bands, so two
--- each way is the rule of thirds.
local grid = {}

-- Each line is drawn twice: a dark line offset by its own width, then the
-- light line on top. A single flat colour disappears into either a dark or a
-- light photo; the pair reads against both.
local PASSES = {
  { offset = 1, r = 0, g = 0, b = 0, a = 0.35 },
  { offset = 0, r = 1, g = 1, b = 1, a = 0.65 },
}

--- Thickness that keeps the grid visible in an exported image, which is
--- viewed at its own size rather than fitted to a window.
---@param width number Image width in pixels
---@param height number Image height in pixels
---@return number
function grid.thicknessFor(width, height)
  return math.max(1, math.floor(math.min(width, height) / 400 + 0.5))
end

--- Draws the grid lines inside a rectangle.
---@param x number Left edge of the image
---@param y number Top edge of the image
---@param w number Width of the image
---@param h number Height of the image
---@param columns number Number of vertical lines
---@param rows number Number of horizontal lines
---@param thickness number|nil Line thickness, defaults to 1
function grid.draw(x, y, w, h, columns, rows, thickness)
  columns = math.max(0, math.floor(columns + 0.5))
  rows = math.max(0, math.floor(rows + 0.5))
  if columns == 0 and rows == 0 then return end

  local t = math.max(1, math.floor((thickness or 1) + 0.5))
  love.graphics.push("all")
  love.graphics.setBlendMode("alpha")
  for _, pass in ipairs(PASSES) do
    love.graphics.setColor(pass.r, pass.g, pass.b, pass.a)
    local offset = pass.offset * t
    for i = 1, columns do
      -- Snapped to whole pixels so a screen-space line is not spread across
      -- two columns of half-lit pixels.
      local lineX = math.floor(x + w * i / (columns + 1) - t / 2 + 0.5) + offset
      love.graphics.rectangle("fill", lineX, y, t, h)
    end
    for i = 1, rows do
      local lineY = math.floor(y + h * i / (rows + 1) - t / 2 + 0.5) + offset
      love.graphics.rectangle("fill", x, lineY, w, t)
    end
  end
  love.graphics.pop()
end

return grid

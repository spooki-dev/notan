local GameObject = require "engine.GameObject"
local Vector2 = require "engine.Vector2"
local colors = require "constants.colors"

--- The Notan mark: a landscape reduced to three flat masses of value, which
--- is what the app does to a photograph. Two peaks over a light sky, painted
--- light / mid / dark with nothing in between — no outlines, no gradients and
--- no text, so it survives being scaled down to 16x16 for a dock or a
--- browser tab.
---
--- Drawn from proportions of a single square, so one definition serves the
--- 1024px app icon and the 64px favicon.
---@class NotanMark : GameObject
local NotanMark = GameObject.extend(GameObject)

-- Unit-square coordinates. The near peak overlaps the far one so the masses
-- interlock rather than stack, and both run off the bottom edge so the dark
-- mass anchors the square.
local PEAK      = { -0.14, 1.02, 0.42, 0.14, 0.92, 1.02 }
local FORE_PEAK = { 0.36, 1.02, 0.72, 0.44, 1.14, 1.02 }

---@param name string Unique name within the scene
---@param size number Width and height of the square, in pixels
---@return NotanMark
function NotanMark:new(name, size)
  NotanMark.super.new(self, name, Vector2(0, 0), size, size)
  self.layer = "ui"
  self.size = size
  return self
end

--- Scales unit-square coordinates to pixels at this object's position.
---@param points number[] Alternating x, y in the range 0..1
---@param x number
---@param y number
---@param size number
---@return number[]
local function scale(points, x, y, size)
  local out = {}
  for i = 1, #points, 2 do
    out[i] = x + points[i] * size
    out[i + 1] = y + points[i + 1] * size
  end
  return out
end

function NotanMark:draw()
  local s = self.size
  local pos = self:getPos()
  local x, y = pos.x, pos.y

  love.graphics.push("all")

  -- Lightest mass: the sky, behind everything.
  love.graphics.setColor(colors.white)
  love.graphics.rectangle("fill", x, y, s, s)

  -- Middle mass: the far peak.
  love.graphics.setColor(colors.dark)
  love.graphics.polygon("fill", scale(PEAK, x, y, s))

  -- Darkest mass: the near peak, drawn over the far one.
  love.graphics.setColor(colors.black)
  love.graphics.polygon("fill", scale(FORE_PEAK, x, y, s))

  love.graphics.pop()
end

return NotanMark

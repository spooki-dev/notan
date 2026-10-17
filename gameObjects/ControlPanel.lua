local GameObject = require "engine.GameObject"
local Vector2 = require "engine.Vector2"
local cacheManager = require "engine.cacheManager"
local inputMap = require "engine.input.inputMap"
local colors = require "constants.colors"

--- Side panel of effect toggles and sliders.
---
--- Drawn by hand rather than composed from engine/ui: this is a dense column
--- of live controls that needs pixel-exact hit testing and click-drag on the
--- sliders, which the flexbox layout and the click-only Button do not cover.
--- The panel keeps no state of its own beyond selection, scroll and drag --
--- every value lives in the Pipeline, so what is drawn is always what will be
--- rendered.
---
--- Rows are flattened into one list (effect headers interleaved with their
--- parameters) so the mouse and the keyboard address exactly the same thing.
--- The list is taller than a phone, so it scrolls: with the wheel, and by
--- dragging it, which is the only gesture a touch screen has.
---@class ControlPanel : GameObject
---@field pipeline Pipeline
---@field rows table[] Flattened { kind, def, param } rows in draw order
---@field selected number Index into rows, for keyboard adjustment
---@field press table|nil The gesture the pointer is in the middle of
local ControlPanel = GameObject.extend(GameObject)

local PANEL_WIDTH = 272
--- Below this window width the panel stops taking a column of its own and
--- floats over the image instead. 272px out of a 414px phone is most of the
--- photo, and a study you cannot see is not worth the room.
local NARROW_WIDTH = 600
local PADDING = 16
local TOP_PAD = 14
local HEADER_H = 30
local PARAM_H = 36
local TOGGLE_H = 26
local TRACK_H = 6
local BOX = 12
local GROUP_GAP = 8
--- Room kept at the foot of the panel for the selected effect's hint, which is
--- pinned there and so must not be scrolled over.
local HINT_H = 64
--- The tab that opens and closes a floating panel. There is no keyboard behind
--- a touch screen, so H is not a way to get the photo back.
local HANDLE_W, HANDLE_H = 26, 76
--- How far a press may wander before it stops being a tap on a row and becomes
--- a drag of the list.
local DRAG_SLOP = 8
local WHEEL_STEP = 48

-- Held left/right ramps up: a short wait before the first repeat, then fast,
-- so one tap nudges by a single step but holding sweeps the whole range.
local REPEAT_DELAY = 0.3
local REPEAT_RATE = 0.03

---@param name string Unique name within the scene
---@param pipeline Pipeline The pipeline whose state this panel edits
function ControlPanel:new(name, pipeline)
  ControlPanel.super.new(self, name, Vector2(0, 0), PANEL_WIDTH, love.graphics.getHeight())
  self.layer = "ui"
  self.pipeline = pipeline
  self.rows = {}
  self.selected = 1
  self.press = nil
  self.repeatTimer = 0
  self.visible = true
  self.scroll = 0
  self.maxScroll = 0
  self.panelWidth = PANEL_WIDTH
  self.overlay = false
  self.windowWidth, self.windowHeight = love.graphics.getDimensions()

  for _, def in ipairs(pipeline.defs) do
    table.insert(self.rows, { kind = "effect", def = def })
    for _, param in ipairs(def.params) do
      table.insert(self.rows, { kind = param.kind, def = def, param = param })
    end
  end

  self:layout()
  return self
end

--- Sizes the panel to the window: the full height of it, anchored to the right
--- edge, floating over the image once the window is too narrow to spare a
--- column. The object's own rect is the area the pointer may hit, which is the
--- panel plus its handle, not the panel alone.
function ControlPanel:layout()
  local w, h = love.graphics.getDimensions()
  self.windowWidth, self.windowHeight = w, h
  self.panelWidth = math.max(160, math.min(PANEL_WIDTH, w - 48))
  self.overlay = w < NARROW_WIDTH

  local left = self.visible and (w - self.panelWidth) or w
  if self.overlay then left = left - HANDLE_W end
  self:setPos(Vector2(left, 0))
  self:setWidth(w - left)
  self:setHeight(h)
  self:setScroll(self.scroll)
end

--- Left edge of the panel body, which is not the object's left edge: the hit
--- rect reaches further out to take in the handle.
---@return number
function ControlPanel:panelLeft()
  return self.windowWidth - self.panelWidth
end

--- The tab that opens and closes the panel while it is floating. It sits on
--- the panel's outer edge when open and on the screen's when closed, so it is
--- always the thing nearest the thumb.
---@return number x, number y, number w, number h
function ControlPanel:handleRect()
  local x = (self.visible and self:panelLeft() or self.windowWidth) - HANDLE_W
  return x, (self.windowHeight - HANDLE_H) / 2, HANDLE_W, HANDLE_H
end

--- Whether a screen point belongs to the panel. The scene asks before panning
--- or zooming, because a floating panel sits inside the image's own area.
---@param x number
---@param y number
---@return boolean
function ControlPanel:containsPoint(x, y)
  local rect = self:getRect()
  return x >= rect.x and x < rect.x + rect.width
    and y >= rect.y and y < rect.y + rect.height
end

--- Width the panel occupies on screen, or 0 while hidden or floating. The
--- scene subtracts this from the window to get the area the image is fitted
--- into, so a floating panel leaves the image the whole width of the device.
---@return number
function ControlPanel:occupiedWidth()
  if not self.visible or self.overlay then return 0 end
  return self.panelWidth
end

--- Shows or hides the panel.
function ControlPanel:toggleVisible()
  self.visible = not self.visible
  self.press = nil
  self:layout()
end

--- Total height of the rows, including the gaps between effect groups.
---@return number
function ControlPanel:contentHeight()
  local total = 0
  for i, row in ipairs(self.rows) do
    if row.kind == "effect" and i > 1 then
      total = total + GROUP_GAP
    end
    total = total + ((row.kind == "effect" and HEADER_H)
      or (row.kind == "toggle" and TOGGLE_H)
      or PARAM_H)
  end
  return total
end

--- Height of the scrolling area: the panel minus its top padding and the hint
--- pinned at the foot.
---@return number
function ControlPanel:viewHeight()
  return math.max(0, self.windowHeight - TOP_PAD - HINT_H)
end

--- Moves the list, clamped so it can never be scrolled past its own ends.
--- Recomputing the limit here rather than caching it means a resize needs no
--- more than another call.
---@param value number
function ControlPanel:setScroll(value)
  self.maxScroll = math.max(0, self:contentHeight() - self:viewHeight())
  self.scroll = math.max(0, math.min(self.maxScroll, value))
end

--- Y position and height of each row, recomputed on demand so there is no
--- layout cache to invalidate.
---@return number y Top of the row
---@return number h Height of the row
function ControlPanel:rowBounds(index)
  local y = TOP_PAD - self.scroll
  for i, row in ipairs(self.rows) do
    local h = (row.kind == "effect" and HEADER_H)
      or (row.kind == "toggle" and TOGGLE_H)
      or PARAM_H
    if row.kind == "effect" and i > 1 then
      y = y + GROUP_GAP
    end
    if i == index then
      return y, h
    end
    y = y + h
  end
  return y, 0
end

--- The slider track rectangle for a parameter row.
---@return number x, number y, number w
function ControlPanel:trackRect(index)
  local rowY = select(1, self:rowBounds(index))
  local x = self:panelLeft() + PADDING
  local w = self.panelWidth - PADDING * 2
  return x, rowY + PARAM_H - TRACK_H - 8, w
end

--- Snaps a value to the parameter's step and clamps it to its range.
---@param param table
---@param value number
---@return number
local function quantise(param, value)
  local steps = math.floor((value - param.min) / param.step + 0.5)
  value = param.min + steps * param.step
  return math.max(param.min, math.min(param.max, value))
end

--- The parameter value formatted for display.
---@param param table
---@param value number
---@return string
local function formatValue(param, value)
  if param.format:find("d") then
    return string.format(param.format, math.floor(value + 0.5))
  end
  return string.format(param.format, value)
end

--- Applies a 0..1 slider position to a parameter.
---@param row table
---@param t number Normalised position along the track
function ControlPanel:setFromTrack(row, t)
  t = math.max(0, math.min(1, t))
  local param = row.param
  self.pipeline:setValue(row.def.id, param.key, quantise(param, param.min + t * (param.max - param.min)))
end

--- Nudges the selected parameter, or flips the selected toggle.
---@param direction number -1 or 1
function ControlPanel:adjust(direction)
  local row = self.rows[self.selected]
  if not row then return end
  if row.kind == "number" then
    local state = self.pipeline:getState(row.def.id)
    local current = state.values[row.param.key]
    self.pipeline:setValue(row.def.id, row.param.key,
      quantise(row.param, current + direction * row.param.step))
  elseif row.kind == "toggle" then
    self:activate()
  elseif row.kind == "effect" then
    self.pipeline:setEnabled(row.def.id, direction > 0)
  end
end

--- Toggles whatever the selected row represents.
function ControlPanel:activate()
  local row = self.rows[self.selected]
  if not row then return end
  if row.kind == "effect" then
    self.pipeline:setEnabled(row.def.id, not self.pipeline:getState(row.def.id).enabled)
  elseif row.kind == "toggle" then
    local state = self.pipeline:getState(row.def.id)
    self.pipeline:setValue(row.def.id, row.param.key,
      state.values[row.param.key] > 0.5 and 0 or 1)
  end
end

--- A function that puts back whatever a press on this row is about to change.
--- Captured before the press acts and called only if the gesture turns out to
--- be a scroll, so flicking the list never leaves an effect altered behind it.
---@param row table
---@return function
function ControlPanel:undoFor(row)
  local state = self.pipeline:getState(row.def.id)
  if row.kind == "effect" then
    local enabled = state.enabled
    return function() self.pipeline:setEnabled(row.def.id, enabled) end
  end
  local key = row.param.key
  local value = state.values[key]
  return function() self.pipeline:setValue(row.def.id, key, value) end
end

--- Moves the keyboard selection, wrapping at both ends.
---@param delta number
function ControlPanel:moveSelection(delta)
  local count = #self.rows
  self.selected = ((self.selected - 1 + delta) % count) + 1
  self:revealSelected()
end

--- Scrolls the selected row into view, so arrowing down a list taller than the
--- panel does not walk off the bottom of it.
function ControlPanel:revealSelected()
  local y, h = self:rowBounds(self.selected)
  local top = TOP_PAD
  local bottom = TOP_PAD + self:viewHeight()
  if y < top then
    self:setScroll(self.scroll - (top - y))
  elseif y + h > bottom then
    self:setScroll(self.scroll + (y + h - bottom))
  end
end

--- Menu actions drive the panel so it works from the keyboard and a gamepad
--- as well as the mouse (see docs/input.md).
---@param name string
function ControlPanel:onActionPressed(name)
  if not self.visible then return end
  if name == "ui_down" then
    self:moveSelection(1)
  elseif name == "ui_up" then
    self:moveSelection(-1)
  elseif name == "ui_accept" then
    self:activate()
  elseif name == "ui_left" then
    self:adjust(-1)
    self.repeatTimer = -REPEAT_DELAY
  elseif name == "ui_right" then
    self:adjust(1)
    self.repeatTimer = -REPEAT_DELAY
  end
end

-- Present so the scene registers the panel for mouse events; the rect test in
-- GameObject:handleMouseDown does the actual work.
function ControlPanel:onMouseOver() end

---@param x number
---@param y number
---@param button number
function ControlPanel:onMouseDown(x, y, button)
  if button ~= 1 then return end

  if self.overlay then
    local hx, hy, hw, hh = self:handleRect()
    if x >= hx and x < hx + hw and y >= hy and y < hy + hh then
      self:toggleVisible()
      return
    end
  end
  if not self.visible then return end

  local top, bottom = TOP_PAD, TOP_PAD + self:viewHeight()
  for i, row in ipairs(self.rows) do
    local rowY, rowH = self:rowBounds(i)
    -- Only rows the scissor actually shows are hittable, so a press on the
    -- hint at the foot does not reach whatever is scrolled underneath it.
    if y >= rowY and y < rowY + rowH and rowY >= top and rowY + rowH <= bottom then
      self.selected = i
      -- The press acts at once, so the panel stays as live under a mouse as it
      -- was, but remembers how to undo itself: the same gesture becomes a drag
      -- of the list if the pointer turns out to be travelling down, not across.
      self.press = { index = i, row = row, x = x, y = y, scroll = self.scroll,
        mode = "row", undo = self:undoFor(row) }
      if row.kind == "number" then
        local trackX, _, trackW = self:trackRect(i)
        self:setFromTrack(row, (x - trackX) / trackW)
      else
        self:activate()
      end
      return
    end
  end

  -- A press on the panel's own background still drags the list.
  self.press = { x = x, y = y, scroll = self.scroll, mode = "row" }
end

--- Wheel over the panel scrolls the list. The scene hands scroll to every
--- object that wants it without hit testing, so the panel checks the pointer.
---@param dx number
---@param dy number
function ControlPanel:handleScroll(dx, dy)
  if not self.visible or dy == 0 then return end
  if not self:containsPoint(love.mouse.getPosition()) then return end
  self:setScroll(self.scroll - dy * WHEEL_STEP)
end

---@param dt number
function ControlPanel:update(dt)
  -- love.js never reports a resize, so the panel checks rather than waits: it
  -- has to be the window's full height whatever changed it.
  local w, h = love.graphics.getDimensions()
  if w ~= self.windowWidth or h ~= self.windowHeight then
    self:layout()
  end

  if not self.visible then return end

  -- The engine forwards mouse presses but not releases, so a gesture ends when
  -- the button is observed to be up rather than on a release event.
  if self.press then
    if love.mouse.isDown(1) then
      local mx, my = love.mouse.getPosition()
      local dx, dy = mx - self.press.x, my - self.press.y
      if self.press.mode == "row" and math.abs(dy) > DRAG_SLOP
        and math.abs(dy) > math.abs(dx) then
        self.press.mode = "scroll"
        if self.press.undo then self.press.undo() end
      end
      if self.press.mode == "scroll" then
        self:setScroll(self.press.scroll - dy)
      elseif self.press.row and self.press.row.kind == "number" then
        local trackX, _, trackW = self:trackRect(self.press.index)
        self:setFromTrack(self.press.row, (mx - trackX) / trackW)
      end
    else
      self.press = nil
    end
  end

  local held = (inputMap.down("ui_left") and -1) or (inputMap.down("ui_right") and 1) or nil
  if held then
    self.repeatTimer = self.repeatTimer + dt
    while self.repeatTimer >= REPEAT_RATE do
      self.repeatTimer = self.repeatTimer - REPEAT_RATE
      self:adjust(held)
    end
  else
    self.repeatTimer = 0
  end
end

--- The tab that opens and closes a floating panel: a thumb-sized target with a
--- chevron pointing the way the panel will go.
function ControlPanel:drawHandle()
  local x, y, w, h = self:handleRect()
  love.graphics.setColor(0.07, 0.07, 0.08, 0.96)
  love.graphics.rectangle("fill", x, y, w, h, 4, 4)
  love.graphics.setColor(1, 1, 1, 0.1)
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 4, 4)
  local cx, cy = x + w / 2, y + h / 2
  local direction = self.visible and 1 or -1
  love.graphics.setColor(colors.yellow[1], colors.yellow[2], colors.yellow[3], 0.9)
  love.graphics.setLineWidth(2)
  love.graphics.line(cx - 3 * direction, cy - 7, cx + 3 * direction, cy, cx - 3 * direction, cy + 7)
  love.graphics.setLineWidth(1)
end

--- A thumb down the panel's inner edge, only while there is more list than
--- panel to put it in.
---@param x number Left edge of the panel body
function ControlPanel:drawScrollbar(x)
  if self.maxScroll <= 0 then return end
  local view = self:viewHeight()
  local thumb = math.max(24, view * view / self:contentHeight())
  local t = self.scroll / self.maxScroll
  love.graphics.setColor(1, 1, 1, 0.18)
  love.graphics.rectangle("fill", x + self.panelWidth - 6, TOP_PAD + (view - thumb) * t,
    3, thumb, 1.5, 1.5)
end

function ControlPanel:draw()
  if self.overlay then self:drawHandle() end
  if not self.visible then
    love.graphics.setColor(1, 1, 1, 1)
    return
  end

  local x, h = self:panelLeft(), self.windowHeight
  local width = self.panelWidth
  local body = cacheManager.getFont("body")
  local small = cacheManager.getFont("small")

  love.graphics.setColor(0.07, 0.07, 0.08, 0.96)
  love.graphics.rectangle("fill", x, 0, width, h)
  love.graphics.setColor(1, 1, 1, 0.08)
  love.graphics.rectangle("fill", x, 0, 1, h)

  -- Rows are clipped to the scrolling area, so a scrolled list never draws
  -- over the hint at the foot or past the top of the panel.
  love.graphics.setScissor(x, TOP_PAD, width, self:viewHeight())
  for i, row in ipairs(self.rows) do
    local rowY, rowH = self:rowBounds(i)
    local state = self.pipeline:getState(row.def.id)
    local isSelected = i == self.selected
    local isLive = state.enabled

    if isSelected then
      love.graphics.setColor(1, 1, 1, 0.07)
      love.graphics.rectangle("fill", x + 4, rowY, width - 8, rowH)
    end

    if row.kind == "effect" then
      -- Checkbox, filled when the effect is contributing to the image.
      local boxY = rowY + (rowH - BOX) / 2
      love.graphics.setColor(1, 1, 1, isLive and 0.9 or 0.35)
      love.graphics.rectangle("line", x + PADDING + 0.5, boxY + 0.5, BOX, BOX)
      if isLive then
        love.graphics.setColor(colors.yellow[1], colors.yellow[2], colors.yellow[3], 1)
        love.graphics.rectangle("fill", x + PADDING + 3, boxY + 3, BOX - 6, BOX - 6)
      end
      love.graphics.setFont(body)
      love.graphics.setColor(1, 1, 1, isLive and 1 or 0.45)
      love.graphics.print(row.def.label, x + PADDING + BOX + 10, rowY + (rowH - body:getHeight()) / 2)
    elseif row.kind == "toggle" then
      local on = state.values[row.param.key] > 0.5
      love.graphics.setFont(small)
      love.graphics.setColor(1, 1, 1, isLive and 0.75 or 0.3)
      love.graphics.print(row.param.label, x + PADDING + BOX + 10, rowY + (rowH - small:getHeight()) / 2)
      local pillW, pillH = 34, 14
      local pillX = x + width - PADDING - pillW
      local pillY = rowY + (rowH - pillH) / 2
      love.graphics.setColor(1, 1, 1, isLive and 0.25 or 0.12)
      love.graphics.rectangle("fill", pillX, pillY, pillW, pillH, 3, 3)
      if on then
        love.graphics.setColor(colors.yellow[1], colors.yellow[2], colors.yellow[3], isLive and 1 or 0.4)
      else
        love.graphics.setColor(1, 1, 1, isLive and 0.4 or 0.2)
      end
      love.graphics.rectangle("fill", on and (pillX + pillW - pillH) or pillX, pillY, pillH, pillH, 3, 3)
    else
      local value = state.values[row.param.key]
      love.graphics.setFont(small)
      love.graphics.setColor(1, 1, 1, isLive and 0.75 or 0.3)
      love.graphics.print(row.param.label, x + PADDING + BOX + 10, rowY + 2)
      local text = formatValue(row.param, value)
      love.graphics.setColor(1, 1, 1, isLive and 0.9 or 0.35)
      love.graphics.print(text, x + width - PADDING - small:getWidth(text), rowY + 2)

      local trackX, trackY, trackW = self:trackRect(i)
      local t = (value - row.param.min) / (row.param.max - row.param.min)
      love.graphics.setColor(1, 1, 1, isLive and 0.16 or 0.08)
      love.graphics.rectangle("fill", trackX, trackY, trackW, TRACK_H, 2, 2)
      if isLive then
        love.graphics.setColor(colors.yellow[1], colors.yellow[2], colors.yellow[3], 0.85)
      else
        love.graphics.setColor(1, 1, 1, 0.22)
      end
      love.graphics.rectangle("fill", trackX, trackY, trackW * t, TRACK_H, 2, 2)
      love.graphics.setColor(1, 1, 1, isLive and 1 or 0.4)
      love.graphics.rectangle("fill", trackX + trackW * t - 2, trackY - 4, 4, TRACK_H + 8, 2, 2)
    end
  end
  love.graphics.setScissor()

  self:drawScrollbar(x)

  -- Hint for the selected effect, pinned to the bottom of the panel.
  local row = self.rows[self.selected]
  if row and row.def.hint then
    love.graphics.setFont(small)
    love.graphics.setColor(1, 1, 1, 0.4)
    love.graphics.printf(row.def.hint, x + PADDING, h - HINT_H, width - PADDING * 2, "left")
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return ControlPanel

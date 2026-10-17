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
--- The panel keeps no state of its own beyond selection and drag — every value
--- lives in the Pipeline, so what is drawn is always what will be rendered.
---
--- Rows are flattened into one list (effect headers interleaved with their
--- parameters) so the mouse and the keyboard address exactly the same thing.
---@class ControlPanel : GameObject
---@field pipeline Pipeline
---@field rows table[] Flattened { kind, def, param } rows in draw order
---@field selected number Index into rows, for keyboard adjustment
---@field dragging table|nil The row whose slider the mouse is holding
local ControlPanel = GameObject.extend(GameObject)

local PANEL_WIDTH = 272
local PADDING = 16
local TITLE_H = 44
local HEADER_H = 30
local PARAM_H = 36
local TOGGLE_H = 26
local TRACK_H = 6
local BOX = 12
local GROUP_GAP = 8

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
  self.dragging = nil
  self.repeatTimer = 0
  self.visible = true

  for _, def in ipairs(pipeline.defs) do
    table.insert(self.rows, { kind = "effect", def = def })
    for _, param in ipairs(def.params) do
      table.insert(self.rows, { kind = param.kind, def = def, param = param })
    end
  end

  self:layout()
  return self
end

--- Anchors the panel to the right edge at the current window size.
function ControlPanel:layout()
  local w, h = love.graphics.getDimensions()
  self:setPos(Vector2(w - PANEL_WIDTH, 0))
  self:setWidth(PANEL_WIDTH)
  self:setHeight(h)
end

--- Width the panel occupies on screen, or 0 while hidden. The scene subtracts
--- this from the window to get the area the image is fitted into.
---@return number
function ControlPanel:occupiedWidth()
  return self.visible and PANEL_WIDTH or 0
end

--- Shows or hides the panel.
function ControlPanel:toggleVisible()
  self.visible = not self.visible
  self.dragging = nil
end

--- Y position and height of each row, recomputed on demand so there is no
--- layout cache to invalidate.
---@return number y Top of the row
---@return number h Height of the row
function ControlPanel:rowBounds(index)
  local y = self:getPos().y + TITLE_H
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
  local x = self:getPos().x + PADDING
  local w = PANEL_WIDTH - PADDING * 2
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

--- Moves the keyboard selection, wrapping at both ends.
---@param delta number
function ControlPanel:moveSelection(delta)
  local count = #self.rows
  self.selected = ((self.selected - 1 + delta) % count) + 1
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
  if button ~= 1 or not self.visible then return end
  for i, row in ipairs(self.rows) do
    local rowY, rowH = self:rowBounds(i)
    if y >= rowY and y < rowY + rowH then
      self.selected = i
      if row.kind == "number" then
        self.dragging = { row = row, index = i }
        local trackX, _, trackW = self:trackRect(i)
        self:setFromTrack(row, (x - trackX) / trackW)
      else
        self:activate()
      end
      return
    end
  end
end

---@param dt number
function ControlPanel:update(dt)
  if not self.visible then return end

  -- The engine forwards mouse presses but not releases, so the drag ends when
  -- the button is observed to be up rather than on a release event.
  if self.dragging then
    if love.mouse.isDown(1) then
      local trackX, _, trackW = self:trackRect(self.dragging.index)
      self:setFromTrack(self.dragging.row, (love.mouse.getX() - trackX) / trackW)
    else
      self.dragging = nil
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

function ControlPanel:draw()
  if not self.visible then return end
  local pos = self:getPos()
  local x, h = pos.x, self.height
  local body = cacheManager.getFont("body")
  local small = cacheManager.getFont("small")

  love.graphics.setColor(0.07, 0.07, 0.08, 0.96)
  love.graphics.rectangle("fill", x, 0, PANEL_WIDTH, h)
  love.graphics.setColor(1, 1, 1, 0.08)
  love.graphics.rectangle("fill", x, 0, 1, h)

  love.graphics.setFont(body)
  love.graphics.setColor(colors.yellow[1], colors.yellow[2], colors.yellow[3], 1)
  love.graphics.print("NOTAN", x + PADDING, PADDING)

  for i, row in ipairs(self.rows) do
    local rowY, rowH = self:rowBounds(i)
    local state = self.pipeline:getState(row.def.id)
    local isSelected = i == self.selected
    local isLive = state.enabled

    if isSelected then
      love.graphics.setColor(1, 1, 1, 0.07)
      love.graphics.rectangle("fill", x + 4, rowY, PANEL_WIDTH - 8, rowH)
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
      local pillX = x + PANEL_WIDTH - PADDING - pillW
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
      love.graphics.print(text, x + PANEL_WIDTH - PADDING - small:getWidth(text), rowY + 2)

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

  -- Hint for the selected effect, pinned to the bottom of the panel.
  local row = self.rows[self.selected]
  if row and row.def.hint then
    love.graphics.setFont(small)
    love.graphics.setColor(1, 1, 1, 0.4)
    love.graphics.printf(row.def.hint, x + PADDING, h - 64, PANEL_WIDTH - PADDING * 2, "left")
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return ControlPanel

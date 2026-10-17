local Scene = require "engine.Scene"
local colors = require "constants.colors"
local Vector4 = require "engine.Vector4"
local cacheManager = require "engine.cacheManager"
local sceneManager = require "engine.sceneManager"
local inputMap = require "engine.input.inputMap"
local glyphs = require "engine.input.glyphs"
local UICanvas = require "engine.ui.UICanvas"
local UIBox = require "engine.ui.UIBox"
local UIText = require "engine.ui.UIText"
local Button = require "engine.ui.Button"
local InputPrompt = require "engine.ui.InputPrompt"
local FocusGroup = require "engine.ui.FocusGroup"

--- Controls screen: every rebindable action with its keyboard/mouse and
--- gamepad bindings. Click a cell (or focus it and press Select) to capture
--- a new binding for that device; Escape cancels. A binding taken from
--- another action is reported. Changes save immediately; Reset restores the
--- shipped defaults. Fully navigable with keyboard or gamepad.
---@class Controls : Scene
local Controls = Scene.extend(Scene)

local ROW_HEIGHT = 26
local CATEGORY_HEIGHT = 20
local LABEL_WIDTH = "30%"
local CELL_WIDTH = "35%"

--- One rebindable cell: an InputPrompt pinned to a device, showing every
--- binding, that can be focused, clicked and put into capture mode.
---@class BindingCell : InputPrompt
local BindingCell = InputPrompt.extend(InputPrompt)

---@param name string
---@param action table inputMap action record
---@param device string "keyboard" | "gamepad"
---@param controls Controls
function BindingCell:new(name, action, device, controls)
  BindingCell.super.new(self, name, action.name, "", {
    device = device,
    showAll = true,
    scale = 1,
    font = "small",
    height = ROW_HEIGHT,
    padding = Vector4(0, 0, 0, 0),
  })
  self.action = action
  self.device = device
  self.controls = controls
  self.focused = false
  self.flash = 0
end

function BindingCell:focus()
  self.focused = true
end

function BindingCell:blur()
  self.focused = false
end

function BindingCell:activate()
  self.controls:beginCapture(self)
end

function BindingCell:onMouseEntered()
  if self.focusGroup then self.focusGroup:setFocus(self) end
end

function BindingCell:onMouseExit()
end

function BindingCell:onClick()
  if self.focusGroup then self.focusGroup:setFocus(self) end
  self:activate()
end

function BindingCell:draw()
  if not self.active then return end
  local pos = self:getPos()
  local x, y = math.floor(pos.x), math.floor(pos.y)
  local w, h = self.width, self.height
  local capturing = self.controls.capturing == self
  if self.focused or capturing then
    local c = capturing and colors.vec4Yellow or colors.vec4Green
    love.graphics.setColor(c.x, c.y, c.z, 0.2)
    love.graphics.rectangle("fill", x - 4, y, w, h)
    love.graphics.setColor(c.x, c.y, c.z, 1)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x - 4 + 0.5, y + 0.5, w - 1, h - 1)
  elseif self.flash > 0 then
    love.graphics.setColor(1, 1, 1, self.flash * 0.3)
    love.graphics.rectangle("fill", x - 4, y, w, h)
  end
  if capturing then
    local font = cacheManager.getFont("small")
    love.graphics.setFont(font)
    love.graphics.setColor(colors.vec4Yellow.x, colors.vec4Yellow.y, colors.vec4Yellow.z, 1)
    love.graphics.print("Press " .. (self.device == "gamepad" and "a button..." or "a key..."), x,
      math.floor(y + (h - font:getHeight()) / 2))
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  BindingCell.super.draw(self)
  if not inputMap.isDefault(self.action.name) then
    -- Small marker: this action no longer has its shipped defaults.
    love.graphics.setColor(colors.vec4Yellow.x, colors.vec4Yellow.y, colors.vec4Yellow.z, 0.8)
    love.graphics.rectangle("fill", x + w - 16, math.floor(y + h / 2) - 2, 4, 4)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

function BindingCell:update(dt)
  if self.flash > 0 then self.flash = math.max(0, self.flash - dt * 2) end
end

-- ---------------------------------------------------------------------------

function Controls:new()
  Controls.super.new(self, "Controls")
  self.backgroundColor = colors.black
  self.focus = FocusGroup({ columns = 2 })
  self.cells = {}
  self.capturing = nil
  self.message = ""
  self.messageTime = 0
end

function Controls:load()
  self.focus:clear()
  self.cells = {}

  local w, h = love.graphics.getDimensions()
  local rows = {}

  -- Header row
  rows[#rows + 1] = UIBox("ControlsHeadings", {
    UIText("ControlsHeadingAction", "ACTION", { font = "small", color = colors.vec4Grey, width = LABEL_WIDTH }),
    UIText("ControlsHeadingKeyboard", "KEYBOARD / MOUSE", { font = "small", color = colors.vec4Grey, width = CELL_WIDTH }),
    UIText("ControlsHeadingGamepad", "GAMEPAD", { font = "small", color = colors.vec4Grey, width = CELL_WIDTH }),
  }, { display = "flex", flexDirection = "row", height = CATEGORY_HEIGHT })

  -- One row per rebindable action, grouped by category in declaration order.
  local lastCategory = nil
  for _, action in ipairs(inputMap.getActions()) do
    if not action.locked then
      if action.category ~= lastCategory then
        lastCategory = action.category
        rows[#rows + 1] = UIText("ControlsCategory" .. action.category, action.category:upper(), {
          font = "small", color = colors.vec4Yellow, height = CATEGORY_HEIGHT,
          margin = Vector4(6, 0, 0, 0),
        })
      end
      local keyboardCell = BindingCell("Cell_" .. action.name .. "_kb", action, inputMap.DEVICE_KEYBOARD, self)
      local gamepadCell = BindingCell("Cell_" .. action.name .. "_pad", action, inputMap.DEVICE_GAMEPAD, self)
      keyboardCell.styles.width = CELL_WIDTH
      gamepadCell.styles.width = CELL_WIDTH
      self.focus:add(keyboardCell):add(gamepadCell)
      self.cells[#self.cells + 1] = keyboardCell
      self.cells[#self.cells + 1] = gamepadCell
      rows[#rows + 1] = UIBox("Row_" .. action.name, {
        UIText("Label_" .. action.name, action.label, { font = "small", color = colors.vec4White, width = LABEL_WIDTH }),
        keyboardCell,
        gamepadCell,
      }, { display = "flex", flexDirection = "row", height = ROW_HEIGHT })
    end
  end

  -- Footer: reset + back buttons, then a hint line.
  local resetButton = Button("ControlsReset", "Reset defaults", { height = 30 })
  local backButton = Button("ControlsBack", "Back", { height = 30 })
  local controls = self
  function resetButton:onClick()
    inputMap.resetToDefaults()
    controls:notify("Defaults restored")
  end

  function backButton:onClick()
    sceneManager.setCurrentScene("Viewer")
  end

  self.focus:add(resetButton):add(backButton)

  self:addGameObject(UICanvas("ControlsUI", {
    UIBox("ControlsPanel", {
      UIText("ControlsTitle", "CONTROLS", { font = "header", color = colors.vec4Yellow }),
      UIText("ControlsIntro",
        "Select a cell and press the input you want. Esc cancels. Changes are saved straight away.",
        { font = "small", color = colors.vec4Grey, margin = Vector4(4, 0, 8, 0) }),
      UIBox("ControlsRows", rows, { gap = 2 }),
      UIBox("ControlsFooter", {
        UIBox("ControlsButtons", { resetButton, backButton }, {
          display = "flex", flexDirection = "row", gap = 10, width = "50%", height = 30,
        }),
      }, { display = "flex", flexDirection = "row", justifyContent = "center", margin = Vector4(16, 0, 0, 0) }),
      UIBox("ControlsHints", {
        InputPrompt("ControlsHintNav", { "ui_up", "ui_left", "ui_down", "ui_right" }, "Navigate", { color = colors.vec4Grey }),
        InputPrompt("ControlsHintAccept", "ui_accept", "Rebind", { color = colors.vec4Grey }),
        InputPrompt("ControlsHintCancel", "ui_cancel", "Back", { color = colors.vec4Grey }),
      }, { display = "flex", flexDirection = "row", gap = 10, height = 32, margin = Vector4(10, 0, 0, 0) }),
    }, { padding = Vector4(0, 0, 0, 0) }),
  }, { width = w, height = h, padding = Vector4(24, 40, 24, 40) }))
  self.builtWidth, self.builtHeight = w, h
end

--- Builds the screen again at the current window size.
---
--- The engine's UI boxes resolve their percentage widths when they load and
--- then keep the number, so a laid-out screen belongs to the window it was
--- laid out in. Rebuilding is the only way to fit a different one, and at a
--- few dozen boxes it is cheap enough to be the whole answer -- better than a
--- second layout path that only runs on resize and so is only half tested.
--- The focused cell survives because `load` rebuilds the rows in the same
--- order, so the index still names the same binding.
function Controls:relayout()
  local canvas = self:getGameObject("ControlsUI")
  if not canvas then return end
  local focused = self.focus.index
  self:removeGameObjectTree(canvas)
  self:load()
  if focused > 0 then
    self.focus:setFocus(focused)
  end
end

--- Engine hook: the window changed size while this screen was in front.
---@param w number
---@param h number
function Controls:resize(w, h)
  self:relayout()
end

function Controls:start()
  self.capturing = nil
  -- Only the current scene is told about a resize, so a window that changed
  -- size while the Viewer was up is news to this screen on the way in.
  local w, h = love.graphics.getDimensions()
  if w ~= self.builtWidth or h ~= self.builtHeight then
    self:relayout()
  end
  if not self.focus:getFocused() then
    self.focus:setFocus(1)
  end
  self:notify("Device: " .. inputMap.getDeviceName(), 2)
end

--- Shows a transient message under the title.
---@param text string
---@param seconds number|nil
function Controls:notify(text, seconds)
  self.message = text
  self.messageTime = seconds or 2.5
end

--- Starts listening for a new binding for a cell's action and device.
---@param cell BindingCell
function Controls:beginCapture(cell)
  if self.capturing then return end
  self.capturing = cell
  local controls = self
  inputMap.startCapture(function(binding)
    controls.capturing = nil
    if not binding then
      controls:notify("Cancelled", 1.5)
      return
    end
    local stolen, err = inputMap.rebind(cell.action.name, binding)
    if not stolen then
      controls:notify(err or "Could not bind", 3)
      return
    end
    cell.flash = 1
    local label = glyphs.label(binding)
    if #stolen > 0 then
      local names = {}
      for i, name in ipairs(stolen) do
        local other = inputMap.getAction(name)
        names[i] = other and other.label or name
      end
      controls:notify(cell.action.label .. " = " .. label .. "  (was " .. table.concat(names, ", ") .. ")", 4)
    else
      controls:notify(cell.action.label .. " = " .. label .. "  Saved", 2.5)
    end
  end, { device = cell.device })
end

--- Action events (ui_cancel backs out; the game's own actions are ignored here).
---@param name string
function Controls:onActionPressed(name)
  if name == "ui_cancel" and not self.capturing then
    sceneManager.setCurrentScene("Viewer")
  end
end

function Controls:update(dt)
  self.focus:update(dt)
  if self.messageTime > 0 then
    self.messageTime = self.messageTime - dt
  end
end

function Controls:draw()
  local w = love.graphics.getWidth()
  local small = cacheManager.getFont("small")
  love.graphics.setFont(small)
  -- Device indicator, top right.
  local device = inputMap.getDeviceName()
  if inputMap.getActiveDevice() == inputMap.DEVICE_GAMEPAD then
    device = device .. "  [" .. inputMap.getGamepadStyle() .. "]"
  end
  love.graphics.setColor(colors.vec4Grey.x, colors.vec4Grey.y, colors.vec4Grey.z, 1)
  love.graphics.printf(device, 0, 28, w - 40, "right")
  -- Status message under the device indicator.
  if self.messageTime > 0 then
    love.graphics.setColor(1, 1, 1, math.min(1, self.messageTime))
    love.graphics.printf(self.message, 0, 48, w - 40, "right")
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Controls

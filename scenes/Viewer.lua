local Scene = require "engine.Scene"
local colors = require "constants.colors"
local cacheManager = require "engine.cacheManager"
local inputMap = require "engine.input.inputMap"
local sceneManager = require "engine.sceneManager"
local saveManager = require "engine.saveManager"
local Pipeline = require "effects.Pipeline"
local effects = require "effects"
local imageIO = require "app.imageIO"
local grid = require "app.grid"
local ControlPanel = require "gameObjects.ControlPanel"

--- The whole app: an image on the left, its effect stack on the right.
---
--- The scene owns the view transform (pan and zoom) and draws the processed
--- canvas itself rather than going through a GameObject, because the image is
--- the document, not an entity in a world: it is positioned in screen space
--- against the viewport, needs its own filtering, and must be swapped for the
--- original the instant a key is held.
---@class Viewer : Scene
local Viewer = Scene.extend(Scene)

--- Whether a path can be opened for reading.
---@param path string
---@return boolean
local function exists(path)
  local file = io.open(path, "rb")
  if not file then return false end
  file:close()
  return true
end

--- First command-line argument that names a readable file, so the app can be
--- launched straight onto an image (`love . ~/pictures/study.jpg`) and set as
--- the system's handler for image files. LOVE passes "." as the game
--- directory, which is skipped along with any flags.
---@return string|nil
local function pathFromArgs()
  if type(arg) ~= "table" then return nil end
  for i = 1, #arg do
    local candidate = arg[i]
    if type(candidate) == "string" and candidate ~= "." and candidate:sub(1, 1) ~= "-"
      and exists(candidate) then
      return candidate
    end
  end
  return nil
end

local ZOOM_MIN, ZOOM_MAX = 0.02, 24
local ZOOM_PER_NOTCH = 1.12
local FIT_MARGIN = 0.96
local MESSAGE_TIME = 4

function Viewer:new()
  Viewer.super.new(self, "Viewer")
  self.backgroundColor = { 0.09, 0.09, 0.1 }

  self.pipeline = Pipeline(effects)
  self.path = nil
  self.sourceWidth, self.sourceHeight = 0, 0

  -- View transform: the image's top-left in screen pixels, plus a scale.
  -- `fitting` means the view re-fits itself whenever the window changes size,
  -- which stays true until the user zooms or pans deliberately.
  self.zoom = 1
  self.offsetX, self.offsetY = 0, 0
  self.fitting = true

  self.panning = false
  self.panX, self.panY = 0, 0
  self.message = nil
  self.messageTimer = 0
end

function Viewer:load()
  saveManager.configure({ filename = "notan.lua", version = 1 })
  self.pipeline:load()

  self.panel = ControlPanel("EffectPanel", self.pipeline)
  self:addGameObject(self.panel)

  self:restoreSettings()
end

function Viewer:start()
  -- Only on the first activation: coming back from the Controls screen must
  -- not reopen the file and throw away the current view.
  if not self.openedFromArgs then
    self.openedFromArgs = true
    local path = pathFromArgs()
    if path then self:openPath(path) end
  end
  self:refitIfNeeded()
end

--- Width available to the image, i.e. the window minus the control panel.
---@return number width
---@return number height
function Viewer:viewport()
  local w, h = love.graphics.getDimensions()
  return w - self.panel:occupiedWidth(), h
end

--- Shows a transient line in the status bar.
---@param text string
function Viewer:notify(text)
  self.message = text
  self.messageTimer = MESSAGE_TIME
  print(text)
end

-- Loading -------------------------------------------------------------------

--- Loads an image from an absolute path and fits it to the viewport.
---@param path string
---@return boolean ok
function Viewer:openPath(path)
  local imageData, err = imageIO.load(path)
  if not imageData then
    self:notify(err or "could not open that file")
    return false
  end
  self.sourceWidth, self.sourceHeight = imageData:getDimensions()
  self.pipeline:setImageData(imageData)
  self.path = path
  self.fitting = true
  self:fit()
  if self.pipeline.scaledDown then
    self:notify(imageIO.basename(path) .. " opened, scaled to "
      .. self.pipeline.width .. "x" .. self.pipeline.height .. " for processing")
  else
    self:notify(imageIO.basename(path) .. " opened")
  end
  return true
end

--- Asks for the OS file picker. The answer is collected in update(), so the
--- window keeps drawing while the dialog is open.
function Viewer:openDialog()
  if imageIO.requestOpenDialog("Open an image") then
    self.awaitingDialog = true
  end
end

--- Engine hook: a file was dragged onto the window.
---@param file love.File
function Viewer:filedropped(file)
  local imageData, err, path = imageIO.loadDropped(file)
  if not imageData then
    self:notify(err or "could not open that file")
    return
  end
  self.sourceWidth, self.sourceHeight = imageData:getDimensions()
  self.pipeline:setImageData(imageData)
  self.path = path
  self.fitting = true
  self:fit()
  self:notify((path and imageIO.basename(path) or "image") .. " opened")
end

--- Writes the processed image next to the source as a PNG, without ever
--- overwriting: a numeric suffix is added until the name is free.
function Viewer:export()
  if not self.pipeline:hasImage() then
    self:notify("nothing to export yet")
    return
  end
  local dir = self.path and imageIO.dirname(self.path) or love.filesystem.getSaveDirectory()
  local stem = self.path and imageIO.stem(self.path) or "image"
  local target = dir .. "/" .. stem .. "-notan.png"
  local n = 2
  while exists(target) do
    target = dir .. "/" .. stem .. "-notan-" .. n .. ".png"
    n = n + 1
  end

  local imageData = self:exportImageData()
  if not imageData then
    self:notify("could not read the processed image back")
    return
  end
  local ok, err = imageIO.savePng(imageData, target)
  self:notify(ok and ("saved " .. imageIO.basename(target)) or (err or "could not save"))
end

--- The processed image as ImageData, with the grid drawn into it when it is
--- switched on. The grid is a screen-space overlay in the window, so for the
--- file it is redrawn at image scale: an exported reference with no grid on it
--- would be the one thing the panel showed that the PNG did not.
---@return love.ImageData|nil
function Viewer:exportImageData()
  local canvas = self.pipeline:getResult()
  if not canvas then return nil end
  if not self.pipeline:isEnabled("grid") then
    return canvas:newImageData()
  end

  local w, h = self.pipeline.width, self.pipeline.height
  local values = self.pipeline:getState("grid").values
  local target = love.graphics.newCanvas(w, h)
  love.graphics.push("all")
  love.graphics.setCanvas(target)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setBlendMode("replace")
  love.graphics.draw(canvas, 0, 0)
  love.graphics.setBlendMode("alpha")
  grid.draw(0, 0, w, h, values.columns, values.rows, grid.thicknessFor(w, h))
  love.graphics.setCanvas()
  love.graphics.pop()
  return target:newImageData()
end

-- View ----------------------------------------------------------------------

--- Scales the image to sit inside the viewport with a small margin.
function Viewer:fit()
  if not self.pipeline:hasImage() then return end
  local vw, vh = self:viewport()
  local iw, ih = self.pipeline.width, self.pipeline.height
  self.zoom = math.min(vw / iw, vh / ih) * FIT_MARGIN
  self.fitting = true
  self:centre()
end

--- Shows the working image at one screen pixel per image pixel.
function Viewer:actualSize()
  if not self.pipeline:hasImage() then return end
  self.zoom = 1
  self.fitting = false
  self:centre()
end

--- Centres the image in the viewport at the current zoom.
function Viewer:centre()
  local vw, vh = self:viewport()
  self.offsetX = (vw - self.pipeline.width * self.zoom) / 2
  self.offsetY = (vh - self.pipeline.height * self.zoom) / 2
end

--- Re-fits only while the view has not been moved by hand.
function Viewer:refitIfNeeded()
  if self.fitting then self:fit() end
end

--- Shows or hides the control panel and hands the image the space it frees.
---
--- A view that is still fitting re-fits to the wider viewport, which is the
--- whole point of hiding the panel. A view the user has zoomed or panned
--- keeps its zoom -- snapping a 400% look at a brushstroke back to fit would
--- cost more than the room is worth -- and is nudged by half the width that
--- changed, so the image keeps its place under the cursor's half of the
--- window instead of hugging one edge.
function Viewer:togglePanel()
  local before = select(1, self:viewport())
  self.panel:toggleVisible()
  local after = select(1, self:viewport())
  if self.fitting then
    self:fit()
  else
    self.offsetX = self.offsetX + (after - before) / 2
  end
end

--- Zooms about a screen point so the pixel under the cursor stays put.
---@param factor number Multiplier applied to the current zoom
---@param screenX number
---@param screenY number
function Viewer:zoomAt(factor, screenX, screenY)
  if not self.pipeline:hasImage() then return end
  local zoom = math.max(ZOOM_MIN, math.min(ZOOM_MAX, self.zoom * factor))
  if zoom == self.zoom then return end
  local imageX = (screenX - self.offsetX) / self.zoom
  local imageY = (screenY - self.offsetY) / self.zoom
  self.zoom = zoom
  self.offsetX = screenX - imageX * zoom
  self.offsetY = screenY - imageY * zoom
  self.fitting = false
end

--- Engine hook: the window changed size.
---@param w number
---@param h number
function Viewer:resize(w, h)
  self.panel:layout()
  self:refitIfNeeded()
end

-- Input ---------------------------------------------------------------------

---@param name string
function Viewer:onActionPressed(name)
  if name == "open_image" then
    self:openDialog()
  elseif name == "export_image" then
    self:export()
  elseif name == "fit_view" then
    self:fit()
  elseif name == "actual_size" then
    self:actualSize()
  elseif name == "toggle_panel" then
    self:togglePanel()
  elseif name == "toggle_grid" then
    local on = not self.pipeline:isEnabled("grid")
    self.pipeline:setEnabled("grid", on)
    self:notify(on and "grid on" or "grid off")
  elseif name == "reset_effects" then
    self.pipeline:reset()
    self:notify("effects reset")
  elseif name == "open_controls" then
    sceneManager.setCurrentScene("Controls")
  end
end

--- Wheel: zoom about the cursor while it is over the image.
---@param dx number
---@param dy number
function Viewer:handleScroll(dx, dy)
  Viewer.super.handleScroll(self, dx, dy)
  if dy == 0 then return end
  local mx, my = love.mouse.getPosition()
  local vw = select(1, self:viewport())
  if mx > vw then return end
  self:zoomAt(ZOOM_PER_NOTCH ^ dy, mx, my)
end

--- A press over the image area starts a pan; the panel handles its own.
function Viewer:handleMouseDown(x, y, button, istouch, presses)
  Viewer.super.handleMouseDown(self, x, y, button, istouch, presses)
  local vw = select(1, self:viewport())
  if button == 1 and x <= vw and self.pipeline:hasImage() then
    self.panning = true
    self.panX, self.panY = x, y
  end
end

function Viewer:update(dt)
  if self.awaitingDialog then
    local finished, path, err = imageIO.pollOpenDialog()
    if finished then
      self.awaitingDialog = false
      if path then
        self:openPath(path)
      elseif err then
        self:notify("file picker failed: " .. err)
      end
    end
  end

  if self.messageTimer > 0 then
    self.messageTimer = self.messageTimer - dt
    if self.messageTimer <= 0 then self.message = nil end
  end

  -- Panning is polled rather than event-driven for the same reason the
  -- panel's sliders are: the engine forwards presses, not releases.
  if self.panning then
    if love.mouse.isDown(1) then
      local mx, my = love.mouse.getPosition()
      local dx, dy = mx - self.panX, my - self.panY
      if dx ~= 0 or dy ~= 0 then
        self.offsetX = self.offsetX + dx
        self.offsetY = self.offsetY + dy
        self.panX, self.panY = mx, my
        -- A deliberate move opts out of re-fitting on resize.
        self.fitting = false
      end
    else
      self.panning = false
    end
  end
end

-- Drawing -------------------------------------------------------------------

function Viewer:draw()
  local vw, vh = self:viewport()
  if not self.pipeline:hasImage() then
    self:drawEmptyState(vw, vh)
    return
  end

  -- Showing the original means skipping the chain entirely, so the comparison
  -- is against the untouched source rather than a "no effects" render of it.
  local showOriginal = inputMap.down("toggle_original")
  local drawable = showOriginal and self.pipeline.source or self.pipeline:getResult()
  local scale = self.zoom
  if showOriginal then
    scale = self.zoom * (self.pipeline.width / self.pipeline.source:getWidth())
  end

  love.graphics.push("all")
  love.graphics.setScissor(0, 0, vw, vh)
  -- Above 1:1 the pixels themselves are the subject, so stop interpolating.
  drawable:setFilter(self.zoom > 1.5 and "nearest" or "linear",
    self.zoom > 1.5 and "nearest" or "linear")
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(drawable, self.offsetX, self.offsetY, 0, scale, scale)
  -- The grid sits over whichever image is showing, including the original:
  -- it measures the composition rather than altering the values.
  if self.pipeline:isEnabled("grid") then
    local values = self.pipeline:getState("grid").values
    grid.draw(self.offsetX, self.offsetY, self.pipeline.width * self.zoom,
      self.pipeline.height * self.zoom, values.columns, values.rows, 1)
  end
  love.graphics.setScissor()
  love.graphics.pop()

  self:drawStatus(vw, vh, showOriginal)
end

---@param vw number
---@param vh number
function Viewer:drawEmptyState(vw, vh)
  local body = cacheManager.getFont("body")
  local small = cacheManager.getFont("small")
  love.graphics.setFont(body)
  love.graphics.setColor(1, 1, 1, 0.75)
  love.graphics.printf("Drop an image here", 0, vh / 2 - 24, vw, "center")
  love.graphics.setFont(small)
  love.graphics.setColor(1, 1, 1, 0.4)
  love.graphics.printf("or press O to open one", 0, vh / 2 + 4, vw, "center")
  love.graphics.setColor(1, 1, 1, 1)
end

---@param vw number
---@param vh number
---@param showOriginal boolean
function Viewer:drawStatus(vw, vh, showOriginal)
  local small = cacheManager.getFont("small")
  love.graphics.setFont(small)
  local left = self.message
  if not left then
    left = (self.path and imageIO.basename(self.path) or "image")
      .. "  " .. self.sourceWidth .. "x" .. self.sourceHeight
      .. "  " .. string.format("%d%%", math.floor(self.zoom * 100 + 0.5))
    if showOriginal then
      left = left .. "  (original)"
    end
  end
  love.graphics.setColor(0, 0, 0, 0.55)
  love.graphics.rectangle("fill", 0, vh - 24, vw, 24)
  love.graphics.setColor(1, 1, 1, self.message and 1 or 0.6)
  love.graphics.print(left, 10, vh - 24 + (24 - small:getHeight()) / 2)

  local hint = "O open   E export   TAB original   0 fit   1 100%   G grid   R reset   H "
    .. (self.panel.visible and "hide panel" or "show panel")
  love.graphics.setColor(1, 1, 1, 0.3)
  love.graphics.print(hint, vw - small:getWidth(hint) - 10, vh - 24 + (24 - small:getHeight()) / 2)
  love.graphics.setColor(1, 1, 1, 1)
end

-- Settings ------------------------------------------------------------------

--- Effect settings are worth keeping between sessions: the stack someone
--- likes for value studies is a preference, not per-image state. The image
--- itself is not restored, only the knobs.
function Viewer:saveSettings()
  local data = { effects = {} }
  for _, def in ipairs(self.pipeline.defs) do
    local state = self.pipeline:getState(def.id)
    local values = {}
    for key, value in pairs(state.values) do
      values[key] = value
    end
    data.effects[def.id] = { enabled = state.enabled, values = values }
  end
  saveManager.save(data)
end

--- Applies saved settings, ignoring anything that no longer exists so an
--- older save never blocks a changed effect list.
function Viewer:restoreSettings()
  local data = saveManager.load()
  if not data or type(data.effects) ~= "table" then return end
  for _, def in ipairs(self.pipeline.defs) do
    local saved = data.effects[def.id]
    if type(saved) == "table" then
      self.pipeline:setEnabled(def.id, saved.enabled == true)
      if type(saved.values) == "table" then
        for _, param in ipairs(def.params) do
          local value = saved.values[param.key]
          if type(value) == "number" then
            self.pipeline:setValue(def.id, param.key, value)
          end
        end
      end
    end
  end
end

--- Engine hook: called by Game:quit on the current scene.
function Viewer:onQuit()
  self:saveSettings()
end

return Viewer

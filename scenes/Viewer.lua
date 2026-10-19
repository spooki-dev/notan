local Scene = require "engine.Scene"
local colors = require "constants.colors"
local cacheManager = require "engine.cacheManager"
local inputMap = require "engine.input.inputMap"
local sceneManager = require "engine.sceneManager"
local saveManager = require "engine.saveManager"
local Pipeline = require "effects.Pipeline"
local effects = require "effects"
local imageIO = require "app.imageIO"
local webBridge = require "app.webBridge"
local filePicker = require "engine.device.filePicker"
local system = require "engine.utils.system"
local pixelFormat = require "engine.utils.pixelFormat"
local grid = require "app.grid"
local cropOverlay = require "app.cropOverlay"
local CropState = require "app.CropState"
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
  -- In a browser the only argument is the .love itself, which is not a photo.
  if system.isWeb() then return nil end
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
  self.crop = CropState()
  self.path = nil
  self.imageName = nil
  self.sourceWidth, self.sourceHeight = 0, 0

  -- View transform: the image's top-left in screen pixels, plus a scale.
  -- `fitting` means the view re-fits itself whenever the window changes size,
  -- which stays true until the user zooms or pans deliberately.
  self.zoom = 1
  self.offsetX, self.offsetY = 0, 0
  self.fitting = true

  self.panning = false
  self.panX, self.panY = 0, 0
  self.cropDrag = nil
  self.cropActive = false
  self.message = nil
  self.messageTimer = 0
end

function Viewer:load()
  saveManager.configure({ filename = "notan.lua", version = 1 })
  self.pipeline:load()

  self.panel = ControlPanel("EffectPanel", { self.pipeline, self.crop })
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
  return self:adopt(imageData, imageIO.basename(path), path)
end

--- Takes a decoded image as the document, whatever brought it in: the command
--- line, a drop, or the device picker. `path` is where it came from on disk
--- and is nil when nothing can say -- a picked file on any platform, because
--- the device API deals in bytes and a name, never a path. Export reads it to
--- decide where the PNG goes, and copes with nil.
---@param imageData love.ImageData
---@param label string Name to show in the status bar
---@param path string|nil Absolute path, when there is one
---@return boolean ok
function Viewer:adopt(imageData, label, path)
  self.sourceWidth, self.sourceHeight = imageData:getDimensions()
  self.pipeline:setImageData(imageData)
  -- The box belongs to the photo, not to the painter, so a new photo always
  -- gets a fresh one centred on it. The dimensions behind it are kept.
  self.crop:setImageSize(self.pipeline.width, self.pipeline.height)
  self.path = path
  self.imageName = label
  self.fitting = true
  self:fit()
  if self.pipeline.scaledDown then
    self:notify(label .. " opened, scaled to "
      .. self.pipeline.width .. "x" .. self.pipeline.height .. " for processing")
  else
    self:notify(label .. " opened")
  end
  return true
end

--- Asks the device for its own file picker. The engine runs the dialog off the
--- main thread on desktop and through the page in a browser, and calls back on
--- a later frame, so the window keeps drawing throughout. On web the browser
--- will not open a dialog except from a tap, so the request is armed rather
--- than opened and the status bar says so (see `drawStatus`).
function Viewer:openDialog()
  if filePicker.isOpen() then return end
  if not filePicker.isAvailable() then
    -- In a browser the page can still raise its own picker, and whatever it
    -- opens arrives through the inbox that update() polls anyway. Everywhere
    -- else an unavailable picker really does mean there is none.
    if system.isWeb() then
      webBridge.requestPicker()
      return
    end
    self:notify("this platform has no file picker; drag an image onto the window")
    return
  end

  filePicker.open({ deliver = "bytes", accept = { "image/*" } }, function(result, event)
    if event ~= "picked" then
      -- "cancelled" is the player changing their mind, which needs no comment.
      if event ~= "cancelled" then
        self:notify("could not open that file")
      end
      return
    end
    local imageData, err = imageIO.decode(result.bytes, result.name)
    if not imageData then
      self:notify(err or "could not open that file")
      return
    end
    self:adopt(imageData, result.name or "image", nil)
  end)
end

--- Engine hook: a file was dragged onto the window.
---@param file love.File
function Viewer:filedropped(file)
  local imageData, err, path = imageIO.loadDropped(file)
  if not imageData then
    self:notify(err or "could not open that file")
    return
  end
  self:adopt(imageData, path and imageIO.basename(path) or "image", path)
end

--- The exported file's name, without extension: the source file's name
--- whatever brought it in, falling back to "image" before anything is open.
---@return string
function Viewer:exportStem()
  if self.path then return imageIO.stem(self.path) end
  if self.imageName then return imageIO.stem(self.imageName) end
  return "image"
end

--- Writes the processed image next to the source as a PNG, without ever
--- overwriting: a numeric suffix is added until the name is free. In a browser
--- there is no "next to the source": the PNG goes to the page, which hands it
--- to the browser to save wherever downloads go.
function Viewer:export()
  if not self.pipeline:hasImage() then
    self:notify("nothing to export yet")
    return
  end

  if system.isWeb() then
    if not pixelFormat.encodable() then
      self:notify("this browser cannot save a PNG; the desktop app can")
      return
    end
    local webImageData = self:exportImageData()
    if not webImageData then
      self:notify("could not read the processed image back")
      return
    end
    local name = self:exportStem() .. "-notan.png"
    local saved, saveErr = webBridge.save(webImageData, name)
    self:notify(saved and ("saved " .. name) or (saveErr or "could not save"))
    return
  end

  -- No path means a picked file, which the device API gives us by name only.
  -- The study has to land somewhere, and the save directory is the one place
  -- every platform lets us write.
  local dir = self.path and imageIO.dirname(self.path) or love.filesystem.getSaveDirectory()
  local stem = self:exportStem()
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

--- The processed image as ImageData: the crop when there is one, with the
--- grid drawn into it when it is switched on.
---
--- The grid is a screen-space overlay in the window, so for the file it is
--- redrawn at image scale: an exported reference with no grid on it would be
--- the one thing the panel showed that the PNG did not. The crop box itself
--- is never drawn in -- the file *is* the box, and drawing its outline would
--- be painting the frame onto the picture.
---@return love.ImageData|nil
function Viewer:exportImageData()
  local canvas = self.pipeline:getResult()
  if not canvas then return nil end
  local rect = self.crop:getRect()
  local gridded = self.pipeline:isEnabled("grid")
  -- Nothing to compose: hand back the chain's own canvas untouched.
  if not gridded and not rect then
    return pixelFormat.toImageData(canvas)
  end

  local ox, oy = 0, 0
  local w, h = self.pipeline.width, self.pipeline.height
  if rect then
    ox, oy, w, h = rect.x, rect.y, rect.w, rect.h
  end

  local target = pixelFormat.newCanvas(w, h)
  love.graphics.push("all")
  love.graphics.setCanvas(target)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setBlendMode("replace")
  love.graphics.draw(canvas, -ox, -oy)
  love.graphics.setBlendMode("alpha")
  if gridded then
    -- Over the crop, not the photo: the grid is for transferring proportions
    -- onto the panel, and the panel is what the crop describes.
    local values = self.pipeline:getState("grid").values
    grid.draw(0, 0, w, h, values.columns, values.rows, grid.thicknessFor(w, h))
  end
  love.graphics.setCanvas()
  love.graphics.pop()
  return pixelFormat.toImageData(target)
end

-- View ----------------------------------------------------------------------

--- The rectangle the view frames: the crop when there is one, the whole
--- working image otherwise. Once a crop is set it is what you are going to
--- paint, so it is what fitting should fill the window with.
---
--- Four numbers rather than a table because fit and centre ask on every
--- window resize.
---@return number x Left edge in working-image pixels
---@return number y Top edge in working-image pixels
---@return number w Width in working-image pixels
---@return number h Height in working-image pixels
function Viewer:documentRect()
  local rect = self.crop:getRect()
  if rect then return rect.x, rect.y, rect.w, rect.h end
  return 0, 0, self.pipeline.width, self.pipeline.height
end

--- Scales the framed rectangle to sit inside the viewport with a small margin.
function Viewer:fit()
  if not self.pipeline:hasImage() then return end
  local vw, vh = self:viewport()
  local _, _, rw, rh = self:documentRect()
  self.zoom = math.min(vw / rw, vh / rh) * FIT_MARGIN
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

--- Centres the framed rectangle in the viewport at the current zoom. The
--- offset is still the image's top-left, so the crop's own position inside
--- the image is subtracted back out.
function Viewer:centre()
  local vw, vh = self:viewport()
  local rx, ry, rw, rh = self:documentRect()
  self.offsetX = (vw - rw * self.zoom) / 2 - rx * self.zoom
  self.offsetY = (vh - rh * self.zoom) / 2 - ry * self.zoom
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
  -- While a panel field is open for typing its keys are digits and letters,
  -- not commands: O is an O, 0 is a zero, and neither opens anything.
  if self.panel:isEditing() then return end
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
  elseif name == "toggle_crop" then
    local on = not self.crop:isEnabled("crop")
    self.crop:setEnabled("crop", on)
    self:notify(on and ("crop " .. self.crop:summary()) or "crop off")
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

--- Wheel: zoom about the cursor while it is over the image. The panel is asked
--- rather than measured off the viewport, because a panel floating over a
--- narrow window is inside the image's own area and still owns its scroll.
---@param dx number
---@param dy number
function Viewer:handleScroll(dx, dy)
  Viewer.super.handleScroll(self, dx, dy)
  if dy == 0 then return end
  local mx, my = love.mouse.getPosition()
  if self.panel:containsPoint(mx, my) then return end
  self:zoomAt(ZOOM_PER_NOTCH ^ dy, mx, my)
end

--- A press over the image area starts a pan; the panel handles its own.
---
--- Before anything is open that same area is the drop target, and pressing it
--- opens the picker instead. A touch screen has neither of the other two ways
--- in -- nothing to drag a file from, no keyboard to press O on -- so the
--- target that says "drop an image here" has to answer a tap as well.
function Viewer:handleMouseDown(x, y, button, istouch, presses)
  Viewer.super.handleMouseDown(self, x, y, button, istouch, presses)
  if button ~= 1 or self.panel:containsPoint(x, y) then return end
  -- A press on the photo is a press out of the panel, which finishes
  -- whatever was being typed there.
  self.panel:commitEdit()
  if not self.pipeline:hasImage() then
    self:openDialog()
    return
  end
  if self:startCropDrag(x, y) then return end
  self.panning = true
  self.panX, self.panY = x, y
end

--- Begins a crop gesture if the press landed on the box or one of its
--- corners, and says whether it did so the caller can fall through to panning.
---
--- Corners are tested first and with a radius wider than the handle is drawn:
--- a fingertip is broader than a cursor, and snatching the whole view when
--- you meant to pull a corner is a jarring thing to do by accident.
---@param x number Screen x
---@param y number Screen y
---@return boolean started
function Viewer:startCropDrag(x, y)
  local rect = self.crop:getRect()
  if not rect then return false end
  local boxX = self.offsetX + rect.x * self.zoom
  local boxY = self.offsetY + rect.y * self.zoom
  local boxW, boxH = rect.w * self.zoom, rect.h * self.zoom

  local handle = cropOverlay.handleAt(boxX, boxY, boxW, boxH, x, y)
  if handle then
    self.cropDrag = {
      mode = "resize",
      handle = handle,
      startRect = { x = rect.x, y = rect.y, w = rect.w, h = rect.h },
    }
    return true
  end

  if x >= boxX and x < boxX + boxW and y >= boxY and y < boxY + boxH then
    self.cropDrag = {
      mode = "move",
      startRect = { x = rect.x, y = rect.y, w = rect.w, h = rect.h },
      startX = (x - self.offsetX) / self.zoom,
      startY = (y - self.offsetY) / self.zoom,
    }
    return true
  end

  return false
end

function Viewer:update(dt)
  -- A photo the page started: its Open button, a drop on the page, a paste.
  -- None of those are answers to a request the app made, so they arrive
  -- through the inbox rather than the device picker (see app/webBridge.lua).
  if system.isWeb() then
    local incoming = webBridge.poll()
    if incoming then
      self:openPath(incoming)
    end
  end

  if self.messageTimer > 0 then
    self.messageTimer = self.messageTimer - dt
    if self.messageTimer <= 0 then self.message = nil end
  end

  -- The crop can be switched on from the panel as well as from the keyboard,
  -- so the refit watches the flag rather than hanging off either path.
  local cropActive = self.crop:isActive()
  if cropActive ~= self.cropActive then
    self.cropActive = cropActive
    self:refitIfNeeded()
  end

  -- The crop box is dragged by polling too, and for the same reason as the
  -- pan below. Note what it does not do: a box drag never clears `fitting`,
  -- because moving the frame is not moving the view.
  if self.cropDrag then
    if love.mouse.isDown(1) then
      local mx, my = love.mouse.getPosition()
      local imageX = (mx - self.offsetX) / self.zoom
      local imageY = (my - self.offsetY) / self.zoom
      if self.cropDrag.mode == "resize" then
        self.crop:resizeFrom(self.cropDrag.handle, self.cropDrag.startRect, imageX, imageY)
      else
        local start = self.cropDrag.startRect
        self.crop:moveTo(start.x + (imageX - self.cropDrag.startX),
          start.y + (imageY - self.cropDrag.startY))
      end
    else
      self.cropDrag = nil
    end
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
  -- Tab holds the original up, and Tab also moves between the panel's typed
  -- fields, so while one is open it is not asking for the original.
  local showOriginal = inputMap.down("toggle_original") and not self.panel:isEditing()
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
  -- it measures the composition rather than altering the values. It divides
  -- the crop when there is one, because the crop is the panel it is there to
  -- help transfer onto.
  if self.pipeline:isEnabled("grid") then
    local values = self.pipeline:getState("grid").values
    local rx, ry, rw, rh = self:documentRect()
    grid.draw(self.offsetX + rx * self.zoom, self.offsetY + ry * self.zoom,
      rw * self.zoom, rh * self.zoom, values.columns, values.rows, 1)
  end
  local rect = self.crop:getRect()
  if rect then
    cropOverlay.draw(self.offsetX, self.offsetY,
      self.pipeline.width * self.zoom, self.pipeline.height * self.zoom,
      self.offsetX + rect.x * self.zoom, self.offsetY + rect.y * self.zoom,
      rect.w * self.zoom, rect.h * self.zoom, cropOverlay.HANDLE)
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
  -- A floating panel covers the right of the image area. The invitation is the
  -- one thing that must be read before anything else can happen, so it centres
  -- in what is left rather than behind the panel.
  local free = vw - self.panel:overlappedWidth()
  love.graphics.setFont(body)
  love.graphics.setColor(1, 1, 1, 0.75)
  love.graphics.printf("Drop an image here", 0, vh / 2 - 24, free, "center")
  love.graphics.setFont(small)
  love.graphics.setColor(1, 1, 1, 0.4)
  -- The narrow layout is the phone one, where there is no key to offer and
  -- tapping is the whole of it.
  love.graphics.printf(self.panel.overlay and "or tap here to choose one"
    or "or click here to choose one, or press O", 0, vh / 2 + 4, free, "center")
  love.graphics.setColor(1, 1, 1, 1)
end

---@param vw number
---@param vh number
---@param showOriginal boolean
function Viewer:drawStatus(vw, vh, showOriginal)
  local small = cacheManager.getFont("small")
  love.graphics.setFont(small)
  local left = self.message
  if not left and filePicker.getState() == "awaitingGesture" then
    -- Browsers open a dialog only from a real tap, so the engine arms the
    -- request and the page puts up its own prompt. Say so rather than look idle.
    left = "waiting for you to confirm the file picker"
  end
  if not left then
    left = (self.imageName or "image")
      .. "  " .. self.sourceWidth .. "x" .. self.sourceHeight
    -- What the export will actually be, which is the number that matters once
    -- a crop is on and is not derivable from the source size.
    local rect = self.crop:getRect()
    if rect then
      left = left .. " -> " .. rect.w .. "x" .. rect.h .. " " .. self.crop:ratioText()
    end
    left = left .. "  " .. string.format("%d%%", math.floor(self.zoom * 100 + 0.5))
    if showOriginal then
      left = left .. "  (original)"
    end
  end
  local baseline = vh - 24 + (24 - small:getHeight()) / 2
  love.graphics.setColor(0, 0, 0, 0.55)
  love.graphics.rectangle("fill", 0, vh - 24, vw, 24)
  love.graphics.setColor(1, 1, 1, self.message and 1 or 0.6)
  love.graphics.print(left, 10, baseline)

  -- The key list is the first thing to go when the window gets tight: it
  -- would run into the file name long before it ran out of window, and the
  -- narrow sizes are phones, which have no keyboard for it to describe.
  local hint = "O open   E export   TAB original   0 fit   1 100%   K crop   G grid   R reset   H "
    .. (self.panel.visible and "hide panel" or "show panel")
  local hintWidth = small:getWidth(hint)
  if small:getWidth(left) + hintWidth + 30 <= vw then
    love.graphics.setColor(1, 1, 1, 0.3)
    love.graphics.print(hint, vw - hintWidth - 10, baseline)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- Settings ------------------------------------------------------------------

--- Effect settings are worth keeping between sessions: the stack someone
--- likes for value studies is a preference, not per-image state. The image
--- itself is not restored, only the knobs.
function Viewer:saveSettings()
  -- The canvas dimensions belong here for the same reason: a 16x20 panel is
  -- still 16x20 next time. The box itself is not saved -- it belongs to the
  -- photo, and the photo is not restored either.
  local cropValues = self.crop:getState("crop").values
  local data = {
    effects = {},
    crop = {
      enabled = self.crop:isEnabled("crop"),
      width = cropValues.width,
      height = cropValues.height,
    },
  }
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
  if not data then return end

  if type(data.crop) == "table" then
    if type(data.crop.width) == "number" then
      self.crop:setValue("crop", "width", data.crop.width)
    end
    if type(data.crop.height) == "number" then
      self.crop:setValue("crop", "height", data.crop.height)
    end
    self.crop:setEnabled("crop", data.crop.enabled == true)
  end

  if type(data.effects) ~= "table" then return end
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

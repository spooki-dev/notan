local Object = require "engine.lib.classic"
local pixelFormat = require "engine.utils.pixelFormat"

--- Longest edge of the working image. Photos straight off a camera are far
--- bigger than any texture we need for judging values, and every effect pass
--- costs width * height, so the source is scaled down once on load instead.
local MAX_EDGE = 4096

--- Runs the effect chain from `effects/init.lua` over a loaded image.
---
--- Owns two canvases at the working size and ping-pongs between them, one pass
--- per enabled effect, exactly like engine/PostProcessing does for the screen.
--- The result is cached: `getResult()` only re-renders after `markDirty()`, so
--- dragging a slider costs one chain run per changed frame and an idle window
--- costs nothing.
---@class Pipeline : Object
---@field defs EffectDef[] Effect definitions, in processing order
---@field state table<string, {enabled: boolean, values: table<string, number>}>
---@field shaders table<string, love.Shader|nil>
---@field image love.Image|nil Working-size copy of the source image
---@field width number Working width
---@field height number Working height
---@field scaledDown boolean Whether the source was larger than MAX_EDGE
local Pipeline = Object:extend()

---@param defs EffectDef[] Ordered effect definitions
function Pipeline:new(defs)
  self.defs = defs
  self.state = {}
  self.shaders = {}
  self.errors = {}
  self.image = nil
  self.source = nil
  self.width = 0
  self.height = 0
  self.scaledDown = false
  self.dirty = true
  self.canvasA = nil
  self.canvasB = nil
  self.result = nil

  for _, def in ipairs(defs) do
    local values = {}
    for _, param in ipairs(def.params) do
      values[param.key] = param.default
    end
    self.state[def.id] = { enabled = def.enabled or false, values = values }
  end
end

--- Compiles every shader. Called once at scene load; a shader that fails to
--- compile is recorded and its effect is skipped rather than killing the app.
--- Overlay entries have no GLSL, so they get no shader and are skipped by
--- `render` and `isAnyEnabled` -- the scene draws them over the image instead.
function Pipeline:load()
  for _, def in ipairs(self.defs) do
    if def.code then
      local ok, shaderOrErr = pcall(love.graphics.newShader, def.code)
      if ok then
        self.shaders[def.id] = shaderOrErr
      else
        self.errors[def.id] = tostring(shaderOrErr)
        print("effect '" .. def.id .. "' failed to compile: " .. tostring(shaderOrErr))
      end
    end
  end
end

--- Replaces the working image. The ImageData is drawn once into a canvas at
--- the working size, so later passes never touch the original resolution.
---@param imageData love.ImageData
function Pipeline:setImageData(imageData)
  local sw, sh = imageData:getDimensions()
  local limits = love.graphics.getSystemLimits()
  local maxEdge = math.min(MAX_EDGE, limits.texturesize or MAX_EDGE)
  local scale = math.min(1, maxEdge / math.max(sw, sh))
  self.scaledDown = scale < 1
  self.width = math.max(1, math.floor(sw * scale))
  self.height = math.max(1, math.floor(sh * scale))

  local source = love.graphics.newImage(imageData)
  source:setFilter("linear", "linear")
  self.source = source

  self.canvasA = pixelFormat.newCanvas(self.width, self.height)
  self.canvasB = pixelFormat.newCanvas(self.width, self.height)
  self.canvasA:setFilter("linear", "linear")
  self.canvasB:setFilter("linear", "linear")
  self.result = nil
  self.dirty = true
end

--- Whether an image is loaded and ready to render.
---@return boolean
function Pipeline:hasImage()
  return self.source ~= nil
end

--- Marks the cached result stale. Called by the UI on every parameter change.
function Pipeline:markDirty()
  self.dirty = true
end

--- The per-effect state table (enabled flag plus parameter values).
---@param id string Effect id
---@return table
function Pipeline:getState(id)
  return self.state[id]
end

--- Turns an effect on or off.
---@param id string
---@param enabled boolean
function Pipeline:setEnabled(id, enabled)
  local state = self.state[id]
  if not state or state.enabled == enabled then return end
  state.enabled = enabled
  self.dirty = true
end

--- Sets one parameter, clamped to the range declared in the effect definition.
---@param id string Effect id
---@param key string Parameter key
---@param value number
function Pipeline:setValue(id, key, value)
  local state = self.state[id]
  if not state then return end
  if state.values[key] == value then return end
  state.values[key] = value
  self.dirty = true
end

--- Restores every parameter and enabled flag to the declared defaults.
function Pipeline:reset()
  for _, def in ipairs(self.defs) do
    local state = self.state[def.id]
    state.enabled = def.enabled or false
    for _, param in ipairs(def.params) do
      state.values[param.key] = param.default
    end
  end
  self.dirty = true
end

--- Whether any effect is enabled (and so whether the processed view differs
--- from the original at all).
---@return boolean
function Pipeline:isAnyEnabled()
  for _, def in ipairs(self.defs) do
    if self.state[def.id].enabled and self.shaders[def.id] then
      return true
    end
  end
  return false
end

--- Whether an effect is switched on, whatever kind it is. Overlays are read
--- through this by the scene that draws them.
---@param id string Effect id
---@return boolean
function Pipeline:isEnabled(id)
  local state = self.state[id]
  return state ~= nil and state.enabled
end

--- Runs the whole chain into the ping-pong canvases.
---@return love.Canvas The canvas holding the processed image
function Pipeline:render()
  love.graphics.push("all")
  love.graphics.setColor(1, 1, 1, 1)
  -- "replace" writes shader output straight into the target: a filter chain
  -- wants the new pixel, not the new pixel blended over the old one.
  love.graphics.setBlendMode("replace")

  local source, dest = self.canvasA, self.canvasB
  love.graphics.setCanvas(source)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.draw(self.source, 0, 0, 0, self.width / self.source:getWidth(),
    self.height / self.source:getHeight())

  for _, def in ipairs(self.defs) do
    local state = self.state[def.id]
    local shader = self.shaders[def.id]
    if state.enabled and shader then
      for pass = 1, (def.passes or 1) do
        love.graphics.setCanvas(dest)
        love.graphics.clear(0, 0, 0, 0)
        love.graphics.setShader(shader)
        def.send(shader, state.values, pass, self.width, self.height)
        love.graphics.draw(source, 0, 0)
        love.graphics.setShader()
        source, dest = dest, source
      end
    end
  end

  love.graphics.setCanvas()
  love.graphics.pop()
  self.result = source
  self.dirty = false
  return source
end

--- The processed image, re-rendering only if a parameter changed.
---@return love.Canvas|nil
function Pipeline:getResult()
  if not self.source then return nil end
  if self.dirty or not self.result then
    return self:render()
  end
  return self.result
end

--- The processed image as ImageData, ready to encode to a file.
---@return love.ImageData|nil
function Pipeline:toImageData()
  local canvas = self:getResult()
  if not canvas then return nil end
  return pixelFormat.toImageData(canvas)
end

return Pipeline

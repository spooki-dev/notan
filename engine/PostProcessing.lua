local Object = require "engine.lib.classic"
local pixelFormat = require "engine.utils.pixelFormat"

---@class PostProcessing : Object
---@field shaders table[] Ordered list of shader definitions
---@field canvas love.Canvas Primary capture canvas
---@field swapCanvas love.Canvas Ping-pong target canvas
---@field time number Elapsed time for animated uniforms
---@field enabled boolean Global toggle
---@field uniforms table Shared uniform values accessible by all shaders
local PostProcessing = Object:extend()

function PostProcessing:new()
  self.shaders = {}
  self.canvas = nil
  self.swapCanvas = nil
  self.time = 0
  self.enabled = true
  self.uniforms = {}
end

--- Creates canvases at current screen dimensions. Call after window setup.
function PostProcessing:load()
  local w, h = love.graphics.getDimensions()
  self.canvas = pixelFormat.newCanvas(w, h)
  self.swapCanvas = pixelFormat.newCanvas(w, h)
end

--- Adds a shader definition to the chain.
---@param shaderDef table { name: string, shader: love.Shader, enabled: boolean, sendUniforms: function(shader, time, w, h) }
function PostProcessing:addShader(shaderDef)
  table.insert(self.shaders, shaderDef)
end

--- Removes a shader from the chain by name.
---@param name string
function PostProcessing:removeShader(name)
  for i, def in ipairs(self.shaders) do
    if def.name == name then
      table.remove(self.shaders, i)
      return
    end
  end
end

--- Redirects all subsequent drawing to the capture canvas.
function PostProcessing:beginCapture()
  if not self.enabled or not self.canvas then return end
  love.graphics.setCanvas(self.canvas)
  love.graphics.clear()
end

--- Restores drawing to the backbuffer.
function PostProcessing:endCapture()
  if not self.enabled or not self.canvas then return end
  love.graphics.setCanvas()
end

--- Runs every enabled shader over a canvas pair and returns the canvas holding the result.
---@param self PostProcessing
---@param source love.Canvas Canvas containing the captured frame
---@param dest love.Canvas Scratch canvas of the same size
---@return love.Canvas
local function runChain(self, source, dest)
  local w, h = source:getDimensions()
  for _, shaderDef in ipairs(self.shaders) do
    if shaderDef.enabled ~= false then
      love.graphics.setCanvas(dest)
      love.graphics.clear()
      love.graphics.setShader(shaderDef.shader)
      shaderDef.sendUniforms(shaderDef.shader, self.time, w, h, self.uniforms)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(source, 0, 0)
      love.graphics.setShader()
      love.graphics.setCanvas()
      source, dest = dest, source
    end
  end
  return source
end

--- Applies all enabled shaders in sequence, then draws the result to screen.
function PostProcessing:apply()
  -- When disabled nothing was captured, so the frame is already on the backbuffer;
  -- drawing the canvas here would paint the last captured frame over it.
  if not self.enabled or not self.canvas then return end

  if #self.shaders == 0 then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.canvas, 0, 0)
    return
  end

  local result = runChain(self, self.canvas, self.swapCanvas)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(result, 0, 0)
end

--- Runs the shader chain over an arbitrary canvas without touching the screen
--- canvases. Uniforms are rebuilt from the scene the same way Game:update does.
---@param source love.Canvas The rendered frame to process (any size)
---@param scene Scene|nil Scene whose updateShaderUniforms hook supplies uniforms
---@return love.Canvas A new canvas holding the processed image
function PostProcessing:process(source, scene)
  for key in pairs(self.uniforms) do
    self.uniforms[key] = nil
  end
  if scene and scene.updateShaderUniforms then
    scene:updateShaderUniforms(self.uniforms, 0)
  end
  local w, h = source:getDimensions()
  local a = pixelFormat.newCanvas(w, h)
  local b = pixelFormat.newCanvas(w, h)
  love.graphics.push("all")
  love.graphics.setCanvas(a)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(source, 0, 0)
  love.graphics.setCanvas()
  local result = runChain(self, a, b)
  love.graphics.pop()
  return result
end

--- Updates elapsed time for shader animations.
---@param dt number Delta time
function PostProcessing:update(dt)
  self.time = self.time + dt
end

--- Recreates canvases at new dimensions. Wire to love.resize.
---@param w number New width
---@param h number New height
function PostProcessing:resize(w, h)
  self.canvas = pixelFormat.newCanvas(w, h)
  self.swapCanvas = pixelFormat.newCanvas(w, h)
end

return PostProcessing

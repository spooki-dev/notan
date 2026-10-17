--- The pixel format canvases are made in, and reading one back as ImageData.
---
--- Desktop GL gives `rgba8`, which is what LOVE's "normal" means there, so on
--- the desktop this module changes nothing. love.js is the reason it exists:
--- its WebGL context offers no `rgba8` canvas at all and "normal" lands on
--- `rgba4`, four bits a channel. That bands every blurred gradient, and
--- `ImageData:encode` has no encoder for it -- which does not raise a Lua
--- error but aborts the process, taking the whole app down with it. `srgba8`
--- is offered instead, so the web build works in that.
---
--- srgba8 costs one wrinkle. The hardware converts between sRGB and linear at
--- the edges of the canvas: encoding what is written and decoding what is
--- read. A chain of passes and the final draw to the screen each do both, so
--- they come out right, but bytes pulled straight back out of the canvas are
--- the encoded ones -- lighter than what was drawn. `toImageData` draws
--- through a shader that undoes the encoding first, so an exported PNG matches
--- what the screen showed.
local pixelFormat = {}

--- Undoes one sRGB encode, so that the hardware's encode on write cancels it
--- and the bytes left in the canvas are the ones that were drawn. The exact
--- piecewise curve, because that is the one the hardware uses.
local LINEARISE = [[
vec4 effect(vec4 color, Image tex, vec2 textureCoords, vec2 screenCoords) {
  vec4 c = Texel(tex, textureCoords);
  vec3 low = c.rgb / 12.92;
  vec3 high = pow(max(c.rgb + 0.055, 0.0) / 1.055, vec3(2.4));
  return vec4(mix(low, high, step(vec3(0.04045), c.rgb)), c.a);
}
]]

local cached = nil
local lineariser = nil

--- The best format available for working canvases.
---@return "rgba8"|"srgba8"|"normal"
function pixelFormat.best()
  if cached then return cached end
  local formats = love.graphics.getCanvasFormats()
  if formats.rgba8 then
    cached = "rgba8"
  elseif formats.srgba8 then
    cached = "srgba8"
  else
    cached = "normal"
  end
  return cached
end

--- Whether ImageData read back from these canvases can be encoded to a file.
--- False means the format has no encoder, and asking for one would abort.
---@return boolean
function pixelFormat.encodable()
  local best = pixelFormat.best()
  return best == "rgba8" or best == "srgba8"
end

--- A canvas in the best available format. Use instead of love.graphics.newCanvas
--- anywhere the contents might be read back or chained through shaders.
---@param w number
---@param h number
---@return love.Canvas
function pixelFormat.newCanvas(w, h)
  return love.graphics.newCanvas(w, h, { format = pixelFormat.best() })
end

---@return love.Shader|nil
local function lineariseShader()
  if lineariser == nil then
    local ok, result = pcall(love.graphics.newShader, LINEARISE)
    lineariser = ok and result or false
    if not ok then print("pixelFormat: lineariser failed to compile: " .. tostring(result)) end
  end
  return lineariser or nil
end

--- Reads a canvas back as ImageData whose bytes are the ones that were drawn.
---@param canvas love.Canvas
---@return love.ImageData
function pixelFormat.toImageData(canvas)
  local shader = pixelFormat.best() == "srgba8" and lineariseShader() or nil
  if not shader then return canvas:newImageData() end

  local w, h = canvas:getDimensions()
  local target = pixelFormat.newCanvas(w, h)
  love.graphics.push("all")
  love.graphics.setCanvas(target)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setColor(1, 1, 1, 1)
  -- "replace" so the shader's output lands in the canvas untouched.
  love.graphics.setBlendMode("replace")
  love.graphics.setShader(shader)
  love.graphics.draw(canvas, 0, 0)
  love.graphics.setShader()
  love.graphics.setCanvas()
  love.graphics.pop()
  return target:newImageData()
end

return pixelFormat

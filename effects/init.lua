--- Ordered effect chain for the image viewer.
---
--- Each entry describes one GPU pass over the working image: its GLSL source,
--- the parameters the UI exposes, and how those parameters reach the shader.
--- `effects/Pipeline.lua` compiles and runs them in the order listed here, so
--- the order is the processing order: soften shapes, then compress the value
--- range, then drain colour, then quantise. That order matters for painting —
--- blurring after posterising would smear the value bands you want to read.
---
--- An entry with `overlay = true` has no GLSL of its own: it carries its
--- parameters here so the panel, the saved settings and the reset action treat
--- it like any other effect, but the viewer draws it over the image instead of
--- the pipeline running it as a pass. The grid is one, because its lines must
--- stay a pixel wide on screen at every zoom.
---
--- Parameter fields:
---   key      identifier sent to the shader as a uniform
---   label    shown in the control panel
---   kind     "number" (slider) or "toggle" (on/off)
---   min/max  slider range
---   step     increment used by keyboard adjustment
---   default  starting value
---   format   string.format pattern for the displayed value
---@class EffectDef
---@field id string
---@field label string
---@field hint string
---@field enabled boolean Whether the effect starts switched on
---@field overlay boolean|nil Drawn over the image by the viewer, not a GPU pass
---@field passes number|nil How many times to run the shader (default 1)
---@field code string|nil GLSL source, omitted by an overlay
---@field params table[]
---@field send fun(shader: love.Shader, values: table, pass: number, w: number, h: number)|nil

local LUMA = "const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);\n"

local blurCode = LUMA .. [[
extern vec2 direction;
extern vec2 texelSize;
extern float radius;

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  if (radius <= 0.0) {
    return Texel(tex, tc);
  }
  // Gaussian sampled on a stride proportional to the radius, so a big radius
  // costs the same 17 taps as a small one.
  float stride = max(radius / 4.0, 1.0);
  float sigma = max(radius, 0.0001);
  vec4 sum = vec4(0.0);
  float total = 0.0;
  for (int i = -8; i <= 8; i++) {
    float offset = float(i) * stride;
    float weight = exp(-(offset * offset) / (2.0 * sigma * sigma));
    sum += Texel(tex, tc + direction * texelSize * offset) * weight;
    total += weight;
  }
  return sum / total;
}
]]

local levelsCode = [[
extern float brightness;
extern float contrast;
extern float gamma;

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec4 c = Texel(tex, tc);
  vec3 rgb = c.rgb + brightness;
  rgb = (rgb - 0.5) * contrast + 0.5;
  rgb = clamp(rgb, 0.0, 1.0);
  rgb = pow(rgb, vec3(1.0 / gamma));
  return vec4(rgb, c.a);
}
]]

local saturationCode = LUMA .. [[
extern float saturation;

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec4 c = Texel(tex, tc);
  float luma = dot(c.rgb, LUMA);
  return vec4(clamp(mix(vec3(luma), c.rgb, saturation), 0.0, 1.0), c.a);
}
]]

local posteriseCode = LUMA .. [[
extern float steps;
extern float byValue;

// Snaps v to one of `n` evenly spaced levels spanning the full 0..1 range, so
// the darkest band is always black and the lightest always white.
float quantise(float v, float n) {
  return floor(clamp(v, 0.0, 0.9999) * n) / (n - 1.0);
}

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec4 c = Texel(tex, tc);
  float n = max(floor(steps + 0.5), 2.0);
  vec3 rgb;
  if (byValue > 0.5) {
    // Quantise brightness only and scale the colour to match, which keeps the
    // hue of each band: the value study a painter blocks in, still in colour.
    float luma = dot(c.rgb, LUMA);
    float target = quantise(luma, n);
    rgb = clamp(c.rgb * (target / max(luma, 0.0001)), 0.0, 1.0);
  } else {
    rgb = vec3(quantise(c.r, n), quantise(c.g, n), quantise(c.b, n));
  }
  return vec4(rgb, c.a);
}
]]

---@type EffectDef[]
return {
  {
    id = "blur",
    label = "Blur",
    hint = "The squint test: loses detail so only the big shapes read.",
    enabled = false,
    passes = 2, -- separable: horizontal, then vertical
    code = blurCode,
    params = {
      { key = "radius", label = "Radius", kind = "number", min = 0, max = 32, step = 0.5, default = 4, format = "%.1f" },
    },
    send = function(shader, values, pass, w, h)
      shader:send("radius", values.radius)
      shader:send("texelSize", { 1 / w, 1 / h })
      shader:send("direction", pass == 1 and { 1, 0 } or { 0, 1 })
    end,
  },
  {
    id = "levels",
    label = "Levels",
    hint = "Push the values apart before quantising so the bands land where you want them.",
    enabled = false,
    code = levelsCode,
    params = {
      { key = "brightness", label = "Brightness", kind = "number", min = -0.5, max = 0.5, step = 0.01, default = 0, format = "%+.2f" },
      { key = "contrast",   label = "Contrast",   kind = "number", min = 0,    max = 2.5, step = 0.02, default = 1, format = "%.2f" },
      { key = "gamma",      label = "Gamma",      kind = "number", min = 0.2,  max = 3,   step = 0.02, default = 1, format = "%.2f" },
    },
    send = function(shader, values)
      shader:send("brightness", values.brightness)
      shader:send("contrast", values.contrast)
      shader:send("gamma", values.gamma)
    end,
  },
  {
    id = "saturation",
    label = "Saturation",
    hint = "Drop to 0 for a pure value study; push past 1 to judge colour temperature.",
    enabled = false,
    code = saturationCode,
    params = {
      { key = "saturation", label = "Amount", kind = "number", min = 0, max = 2, step = 0.02, default = 1, format = "%.2f" },
    },
    send = function(shader, values)
      shader:send("saturation", values.saturation)
    end,
  },
  {
    id = "posterise",
    label = "Posterise",
    hint = "The value bands to block in. Two or three steps first, then refine.",
    enabled = true,
    code = posteriseCode,
    params = {
      { key = "steps",   label = "Steps",    kind = "number", min = 2, max = 16, step = 1, default = 4, format = "%d" },
      { key = "byValue", label = "By value", kind = "toggle", default = 1 },
    },
    send = function(shader, values)
      shader:send("steps", values.steps)
      shader:send("byValue", values.byValue)
    end,
  },
  {
    id = "grid",
    label = "Grid",
    hint = "Thirds or quarters for transferring proportions. Drawn over the image and included in the export.",
    enabled = false,
    overlay = true,
    params = {
      { key = "columns", label = "Vertical lines",   kind = "number", min = 0, max = 16, step = 1, default = 2, format = "%d" },
      { key = "rows",    label = "Horizontal lines", kind = "number", min = 0, max = 16, step = 1, default = 2, format = "%d" },
    },
  },
}

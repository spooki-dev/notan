local Scene = require "engine.Scene"
local cacheManager = require "engine.cacheManager"
local colors = require "constants.colors"
local glyphs = require "engine.input.glyphs"

--- Preloads shared assets. Registered first in main.lua so its load() runs
--- before any other scene builds objects that depend on cached fonts.
--- The font keys below (header, subheader, body, small) are relied on by engine/ui.
---@class Preload : Scene
local Preload = Scene.extend(Scene)

function Preload:new()
  Preload.super.new(self, "Preload")
  self.backgroundColor = colors.black
end

function Preload:load()
  -- nil path means LOVE's built-in default font, so the UI reads as plain system
  -- text rather than the pixel face.
  cacheManager.preloadFont("header", nil, 24)
  cacheManager.preloadFont("subheader", nil, 20)
  cacheManager.preloadFont("body", nil, 15)
  cacheManager.preloadFont("small", nil, 12)
  -- Button prompt glyphs (Kenney Input Prompts Pixel 16x), read by engine/input/glyphs.lua.
  cacheManager.preloadImage(glyphs.IMAGE_KEY, glyphs.IMAGE_PATH)
end

return Preload

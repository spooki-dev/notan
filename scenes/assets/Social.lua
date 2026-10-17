local Scene = require "engine.Scene"
local colors = require "constants.colors"
local Vector4 = require "engine.Vector4"
local UICanvas = require "engine.ui.UICanvas"
local UIBox = require "engine.ui.UIBox"
local Wordmark = require "gameObjects.Wordmark"

--- Social / OpenGraph card (1200x630).
--- Constructed by engine/AssetExporter.lua with the target pixel size.
---@class AssetSocial : Scene
local AssetSocial = Scene.extend(Scene)

---@param width number Output width in pixels
---@param height number Output height in pixels
function AssetSocial:new(width, height)
  AssetSocial.super.new(self, "AssetSocial")
  self.width = width
  self.height = height
  self.backgroundColor = colors.black
end

function AssetSocial:load()
  local padding = 48
  self:addGameObject(UICanvas("AssetSocialUI", {
    Wordmark("AssetSocialMark", {
      lines = { "NOTAN" },
      subtitle = "Built with spooki-love",
      titleSize = 96,
      subtitleSize = 32,
      canvasHeight = self.height - padding * 2,
    }),
  }, { width = self.width, height = self.height, padding = Vector4(padding, padding, padding, padding) }))
end

return AssetSocial

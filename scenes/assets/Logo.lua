local Scene = require "engine.Scene"
local colors = require "constants.colors"
local Vector4 = require "engine.Vector4"
local UICanvas = require "engine.ui.UICanvas"
local UIBox = require "engine.ui.UIBox"
local Wordmark = require "gameObjects.Wordmark"

--- Transparent wordmark for press kits and banners (1600x400). Exported with transparent = true, so nothing here paints a background.
--- Constructed by engine/AssetExporter.lua with the target pixel size.
---@class AssetLogo : Scene
local AssetLogo = Scene.extend(Scene)

---@param width number Output width in pixels
---@param height number Output height in pixels
function AssetLogo:new(width, height)
  AssetLogo.super.new(self, "AssetLogo")
  self.width = width
  self.height = height
  self.backgroundColor = colors.black
end

function AssetLogo:load()
  local padding = 16
  self:addGameObject(UICanvas("AssetLogoUI", {
    Wordmark("AssetLogoMark", {
      lines = { "NOTAN" },
      subtitle = "Built with spooki-love",
      titleSize = 72,
      subtitleSize = 24,
      canvasHeight = self.height - padding * 2,
    }),
  }, { width = self.width, height = self.height, padding = Vector4(padding, padding, padding, padding) }))
end

return AssetLogo

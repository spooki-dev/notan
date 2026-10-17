local Scene = require "engine.Scene"
local colors = require "constants.colors"
local Vector4 = require "engine.Vector4"
local UICanvas = require "engine.ui.UICanvas"
local UIBox = require "engine.ui.UIBox"
local Wordmark = require "gameObjects.Wordmark"

--- Wide cover / banner (1920x1080).
--- Constructed by engine/AssetExporter.lua with the target pixel size.
---@class AssetWide : Scene
local AssetWide = Scene.extend(Scene)

---@param width number Output width in pixels
---@param height number Output height in pixels
function AssetWide:new(width, height)
  AssetWide.super.new(self, "AssetWide")
  self.width = width
  self.height = height
  self.backgroundColor = colors.black
end

function AssetWide:load()
  local padding = 64
  self:addGameObject(UICanvas("AssetWideUI", {
    Wordmark("AssetWideMark", {
      lines = { "NOTAN" },
      subtitle = "Built with spooki-love",
      titleSize = 128,
      subtitleSize = 48,
      canvasHeight = self.height - padding * 2,
    }),
  }, { width = self.width, height = self.height, padding = Vector4(padding, padding, padding, padding) }))
end

return AssetWide

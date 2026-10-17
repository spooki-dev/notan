local Scene = require "engine.Scene"
local colors = require "constants.colors"
local Vector4 = require "engine.Vector4"
local UICanvas = require "engine.ui.UICanvas"
local UIBox = require "engine.ui.UIBox"
local Wordmark = require "gameObjects.Wordmark"

--- itch.io cover image (630x500).
--- Constructed by engine/AssetExporter.lua with the target pixel size.
---@class AssetCover : Scene
local AssetCover = Scene.extend(Scene)

---@param width number Output width in pixels
---@param height number Output height in pixels
function AssetCover:new(width, height)
  AssetCover.super.new(self, "AssetCover")
  self.width = width
  self.height = height
  self.backgroundColor = colors.black
end

function AssetCover:load()
  local padding = 24
  self:addGameObject(UICanvas("AssetCoverUI", {
    Wordmark("AssetCoverMark", {
      lines = { "NOTAN" },
      subtitle = "Built with spooki-love",
      titleSize = 64,
      subtitleSize = 16,
      canvasHeight = self.height - padding * 2,
    }),
  }, { width = self.width, height = self.height, padding = Vector4(padding, padding, padding, padding) }))
end

return AssetCover

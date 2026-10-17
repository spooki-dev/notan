local Scene = require "engine.Scene"
local colors = require "constants.colors"
local Vector4 = require "engine.Vector4"
local UICanvas = require "engine.ui.UICanvas"
local UIBox = require "engine.ui.UIBox"
local Wordmark = require "gameObjects.Wordmark"

--- Favicon (64x64): single-letter monogram in a thin frame.
--- Constructed by engine/AssetExporter.lua with the target pixel size.
---@class AssetFavicon : Scene
local AssetFavicon = Scene.extend(Scene)

---@param width number Output width in pixels
---@param height number Output height in pixels
function AssetFavicon:new(width, height)
  AssetFavicon.super.new(self, "AssetFavicon")
  self.width = width
  self.height = height
  self.backgroundColor = colors.black
end

function AssetFavicon:load()
  local inset = 2
  local border = 4
  local innerHeight = self.height - inset * 2
  self:addGameObject(UICanvas("AssetFaviconUI", {
    UIBox("AssetFaviconFrame", {
      Wordmark("AssetFaviconMark", {
        lines = { "P" },
        titleSize = 48,
        canvasHeight = innerHeight - border * 2,
      }),
    }, {
      height = innerHeight - border * 2,
      border = Vector4(border, border, border, border),
      borderColor = colors.vec4Green,
      padding = Vector4(border, border, border, border),
    }),
  }, { width = self.width, height = self.height, padding = Vector4(inset, inset, inset, inset) }))
end

return AssetFavicon

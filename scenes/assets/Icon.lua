local Scene = require "engine.Scene"
local colors = require "constants.colors"
local Vector4 = require "engine.Vector4"
local UICanvas = require "engine.ui.UICanvas"
local UIBox = require "engine.ui.UIBox"
local Wordmark = require "gameObjects.Wordmark"

--- Square app icon (1024x1024): framed three-line wordmark. Source for the .icns and .ico.
--- Constructed by engine/AssetExporter.lua with the target pixel size.
---@class AssetIcon : Scene
local AssetIcon = Scene.extend(Scene)

---@param width number Output width in pixels
---@param height number Output height in pixels
function AssetIcon:new(width, height)
  AssetIcon.super.new(self, "AssetIcon")
  self.width = width
  self.height = height
  self.backgroundColor = colors.black
end

function AssetIcon:load()
  local inset = 64
  local border = 32
  local innerHeight = self.height - inset * 2
  self:addGameObject(UICanvas("AssetIconUI", {
    UIBox("AssetIconFrame", {
      Wordmark("AssetIconMark", {
        lines = { "NOTAN" },
        titleSize = 96,
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

return AssetIcon

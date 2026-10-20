local Scene = require "engine.Scene"
local colors = require "constants.colors"
local NotanMark = require "gameObjects.NotanMark"

--- Square app icon (1024x1024): the Notan mark, full bleed. Source for the
--- .icns and the .ico.
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
  -- Full bleed: macOS and Windows both put the icon in a frame of their own,
  -- and an inset frame of ours only shrinks the mark inside it.
  self:addGameObject(NotanMark("AssetIconMark", math.min(self.width, self.height)))
end

return AssetIcon

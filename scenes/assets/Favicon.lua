local Scene = require "engine.Scene"
local colors = require "constants.colors"
local NotanMark = require "gameObjects.NotanMark"

--- Favicon (64x64): the same mark as the app icon, which is the whole point
--- of it having no text in it.
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
  self:addGameObject(NotanMark("AssetFaviconMark", math.min(self.width, self.height)))
end

return AssetFavicon

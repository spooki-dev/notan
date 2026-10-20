local sceneManager = require "engine.sceneManager"

--- Renders scenes offscreen at exact pixel sizes and writes them as PNGs.
--- Used to generate marketing art (icons, covers, logos) from live game
--- scenes so the images follow the game's fonts and colours.
---
--- An asset entry looks like:
---   { name = "icon", scene = IconScene, width = 1024, height = 1024,
---     transparent = false, postProcess = false }
--- `scene` is a Scene constructor called as `ctor(width, height)`, or the
--- name of a scene already registered with sceneManager. An item may set its
--- own `outputDir`, relative to the project root, which is how an asset the
--- game itself loads at runtime lands somewhere that ships inside the .love.
local AssetExporter = {}

---@class AssetItem
---@field name string Output file name without extension
---@field scene function|string Scene constructor taking (width, height), or a registered scene name
---@field width number Output width in pixels
---@field height number Output height in pixels
---@field transparent boolean|nil Clear to transparent instead of the scene background
---@field postProcess boolean|nil Run the post-processing shader chain over the result
---@field outputDir string|nil Write this one asset elsewhere, relative to the project root

---@class AssetConfig
---@field outputDir string|nil Directory relative to the project root (default "assets/generated")
---@field items AssetItem[] Assets to export

--- Resolves an asset's scene constructor.
---@param asset AssetItem
---@return function
local function resolveConstructor(asset)
  if type(asset.scene) == "string" then
    local ctor = sceneManager.getSceneConstructor(asset.scene)
    assert(ctor, "AssetExporter: no registered scene named " .. asset.scene)
    return ctor
  end
  assert(type(asset.scene) == "function" or type(asset.scene) == "table",
    "AssetExporter: asset '" .. tostring(asset.name) .. "' needs a scene constructor or name")
  return asset.scene
end

--- Renders one asset to a canvas.
---@param asset AssetItem
---@param postProcessing PostProcessing|nil Used when asset.postProcess is set
---@return love.Canvas
function AssetExporter.render(asset, postProcessing)
  assert(asset.name and asset.width and asset.height, "AssetExporter: asset needs name, width and height")
  assert(not (asset.transparent and asset.postProcess),
    asset.name .. ": shaders force alpha to 1, render transparent assets without postProcess")

  local ctor = resolveConstructor(asset)
  local scene = ctor(asset.width, asset.height)
  -- Mirror sceneManager.addScene / setCurrentScene without registering the scene.
  if scene.load then scene:load() end
  scene:handleLoad()
  scene.loaded = true
  if scene.start then scene:start() end
  scene:handleUpdate(0)

  local canvas = love.graphics.newCanvas(asset.width, asset.height)
  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  if asset.transparent then
    love.graphics.clear(0, 0, 0, 0)
  else
    -- Scene:handleDraw only sets the background colour, it never clears.
    local bg = scene.backgroundColor or { 0, 0, 0 }
    love.graphics.clear(bg[1], bg[2], bg[3], 1)
  end
  scene:handleDraw()
  love.graphics.pop()

  if asset.postProcess and postProcessing then
    canvas = postProcessing:process(canvas, scene)
  end
  return canvas
end

--- Encodes a canvas as PNG and writes it with plain io so the file can land
--- outside LÖVE's save directory.
---@param canvas love.Canvas
---@param path string Absolute or project-relative file path
local function writePng(canvas, path)
  local png = canvas:newImageData():encode("png"):getString()
  local file, err = io.open(path, "wb")
  assert(file, "AssetExporter: cannot open " .. path .. ": " .. tostring(err))
  file:write(png)
  file:close()
end

--- Exports every configured asset to outputDir.
---@param assets AssetConfig
---@param outputDir string Directory to write into (created if missing)
---@param postProcessing PostProcessing|nil
function AssetExporter.export(assets, outputDir, postProcessing)
  assert(type(assets) == "table" and type(assets.items) == "table", "AssetExporter: assets.items must be a table")
  local root = love.filesystem.getSource()
  local made = {}
  for _, asset in ipairs(assets.items) do
    -- A per-item directory is relative to the project root, the same way the
    -- shared one is resolved by the caller.
    local dir = asset.outputDir and (root .. "/" .. asset.outputDir) or outputDir
    if not made[dir] then
      os.execute(string.format('mkdir -p "%s"', dir))
      made[dir] = true
    end
    local path = dir .. "/" .. asset.name .. ".png"
    writePng(AssetExporter.render(asset, postProcessing), path)
    print(string.format("exported %s (%dx%d)", path, asset.width, asset.height))
  end
end

return AssetExporter

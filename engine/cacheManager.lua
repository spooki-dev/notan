---@class Spritesheet
---@field image love.Image
---@field quads table<string, love.Quad>

---@class cacheManager
---@field images table<string, love.Image>
---@field spritesheets table<string, Spritesheet>
---@field sounds table<string, love.Source>
---@field music table<string, love.Source>
---@field fonts table<string, love.Font>
---@field preloadImage fun(key: string, path: string): nil
---@field getImage fun(key: string): love.Image
---@field preloadSpritesheet fun(key: string, path: string, width: number, height: number, keys: table<string>): nil
---@field getSpritesheet fun(key: string): Spritesheet
---@field preloadSound fun(key: string, path: string): nil
---@field addSound fun(key: string, source: love.Source): nil
---@field hasSound fun(key: string): boolean
---@field getSound fun(key: string): love.Source
---@field preloadMusic fun(key: string, path: string): nil
---@field getMusic fun(key: string): love.Source
---@field preloadFont fun(key: string, path: string|nil, size: number, hinting: love.HintingMode|nil): nil
---@field hasFont fun(key: string): boolean
---@field getFont fun(key: string): love.Font
---@field getSpritePosition fun(sourceW: number, frameW: number, frameH: number, index: number): table<number>

local cacheManager = {}
local images = {}
local spritesheets = {}
local sounds = {}
local music = {}
local fonts = {}

function cacheManager.preloadImage(key, path)
  if not images[key] then
    local image = love.graphics.newImage(path)
    images[key] = image
  else
    error("Image already preloaded: " .. key)
  end
end

function cacheManager.getImage(key)
  if images[key] then
    return images[key]
  else
    error("Image not found in cache: " .. key)
  end
end

--- Preloads a spritesheet into the cache
--- @param key string - The key to identify the spritesheet
--- @param path string - The path to the spritesheet image
--- @param frameWidth number - The width of the sprite
--- @param frameHeight number - The height of the sprite
--- @param keys table<string> - A list of keys for the individual sprites in the spritesheet
function cacheManager.preloadSpritesheet(key, path, frameWidth, frameHeight, keys)
  if not spritesheets[key] then
    local spritesheet = {
      image = love.graphics.newImage(path),
      quads = {}
    }

    for index, key in ipairs(keys) do
      local pos = cacheManager.getSpritePosition(spritesheet.image:getWidth(), frameWidth, frameHeight, index - 1)
      local quad = love.graphics.newQuad(pos[1], pos[2], frameWidth, frameHeight, spritesheet.image:getDimensions())
      spritesheet.quads[key] = quad
    end

    spritesheets[key] = spritesheet
  else
    error("Spritesheet already preloaded: " .. key)
  end
end

function cacheManager.getSpritePosition(sourceW, frameW, frameH, index)
  local columns = sourceW / frameW
  local x = (index % columns) * frameW
  local y = math.floor(index / columns) * frameH
  return { x, y }
end

---@param key string The key to look up the spritesheet
---@return Spritesheet The cached spritesheet object
function cacheManager.getSpritesheet(key)
  if spritesheets[key] then
    return spritesheets[key]
  else
    error("Spritesheet not found in cache: " .. key)
  end
end

--- Registers an already-built Source (for example one synthesised with
--- engine/utils/synth.lua) under a key.
--- @param key string Cache key
--- @param source love.Source The Source to cache
function cacheManager.addSound(key, source)
  if not sounds[key] then
    sounds[key] = source
  else
    error("Sound already preloaded: " .. key)
  end
end

--- Loads a sound file as a static Source and caches it under a key
--- @param key string Cache key
--- @param path string Path to the audio file
function cacheManager.preloadSound(key, path)
  cacheManager.addSound(key, love.audio.newSource(path, "static"))
end

--- Whether a sound is cached under a key
--- @param key string Cache key
--- @return boolean
function cacheManager.hasSound(key)
  return sounds[key] ~= nil
end

---Gets a sound from the cache
---@param key string The key to look up the sound
---@return love.Source The cached sound object
function cacheManager.getSound(key)
  if sounds[key] then
    return sounds[key]
  else
    error("Sound not found in cache: " .. key)
  end
end

function cacheManager.preloadMusic(key, path)
  if not music[key] then
    local musicTrack = love.audio.newSource(path, "stream")
    music[key] = musicTrack
  else
    error("Music already preloaded: " .. key)
  end
end

--- Preloads a font under a key
--- @param key string Cache key
--- @param path string|nil Path to the font file, or nil for LOVE's built-in font
--- @param size number Point size
--- @param hinting love.HintingMode|nil Optional hinting mode ("normal", "light", "mono", "none")
function cacheManager.preloadFont(key, path, size, hinting)
  if not fonts[key] then
    local font
    if path then
      font = love.graphics.newFont(path, size, hinting)
    else
      font = love.graphics.newFont(size, hinting)
    end
    fonts[key] = font
  else
    error("Font already preloaded: " .. key)
  end
end

--- Whether a font is cached under a key
--- @param key string Cache key
--- @return boolean
function cacheManager.hasFont(key)
  return fonts[key] ~= nil
end

function cacheManager.getFont(key)
  if fonts[key] then
    return fonts[key]
  else
    error("Font not found in cache: " .. key)
  end
end

--- Gets a music track from the cache
--- @param key string The key to look up the music
--- @return love.Source The cached music object
function cacheManager.getMusic(key)
  if music[key] then
    return music[key]
  else
    error("Music not found in cache: " .. key)
  end
end

return cacheManager

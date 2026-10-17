--- Keeps the love.js window the size of the page frame around it.
---
--- LÖVE reads its window size from the canvas once, when it starts, and a
--- browser frame changes size constantly: a phone rotates, a toolbar wraps,
--- someone drags the window edge. A page that cannot tell the app about it has
--- only one move left -- scale the canvas with CSS -- and that shrinks the
--- whole app rather than giving it the room, which is how a 1024px layout ends
--- up at 40% on a phone.
---
--- So the page writes the size it wants into the bridge directory (see
--- engine/device/webBridge.lua) and this applies it from the inside with
--- `love.window.setMode`, the one call that can resize a love.js canvas. The
--- result is an ordinary resize: `Game:resize` runs, `postProcessing` rebuilds
--- its canvases and every scene's `resize` fires, so web and desktop re-lay out
--- through exactly the same path.
---
--- Nothing here runs off the web. `apply` is a file read of a dozen bytes and
--- a comparison, which is cheap enough for every frame.

local system = require "engine.utils.system"
local webBridge = require "engine.device.webBridge"

local webWindow = {}

--- Smallest window worth asking for. Matches the floor a page should clamp to
--- and stops a frame collapsed to nothing (a hidden tab, a mid-animation
--- container) from taking the app down to an unusable size it cannot recover
--- from on its own.
local MIN = 64

--- Resizes the window if the page has asked for a size it is not already.
---
--- The comparison is against the window's real size rather than the last value
--- applied, so a request that did not take is retried on the next frame and a
--- resize from anywhere else is not fought over.
--- @return boolean changed Whether the window was resized
--- @return number|nil width The new width, when it changed
--- @return number|nil height The new height, when it changed
function webWindow.apply()
  if not system.isWeb() then return false end

  local width, height = webBridge.readWindowSize()
  if not width or width < MIN or height < MIN then return false end

  local currentWidth, currentHeight = love.graphics.getDimensions()
  if width == currentWidth and height == currentHeight then return false end

  -- The current flags are carried over so this only ever changes the size:
  -- rebuilding them from defaults would drop fullscreen, vsync and the rest.
  local _, _, flags = love.window.getMode()
  local ok = pcall(love.window.setMode, width, height, flags)
  if not ok then return false end

  -- setMode is not guaranteed to raise a resize event, and the size it gives
  -- may be clamped by the window's minimum, so the caller is told what the
  -- window actually became rather than what was asked for.
  return true, love.graphics.getDimensions()
end

return webWindow

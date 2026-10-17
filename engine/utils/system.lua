--- Platform queries. The engine branches on the OS in very few places and they
--- all come through here: the love.js build has no window position to restore
--- and no threads, and the mobile builds reach the file picker and the camera
--- through a native module rather than a subprocess (see
--- engine/device/backends.lua).

local MOBILE = { Android = true, iOS = true }
local DESKTOP = { ["OS X"] = true, Windows = true, Linux = true }

--- The LÖVE OS name: "OS X", "Windows", "Linux", "Android", "iOS" or "Web",
--- and "Unknown" when love.system is unavailable (headless tooling).
--- @return string
local function getOS()
  if not love.system or not love.system.getOS then
    return "Unknown"
  end
  return love.system.getOS()
end

--- True under love.js.
--- @return boolean
local function isWeb()
  return love.system.getOS and love.system.getOS() == "Web"
end

--- True on Android and iOS. The web build running in a phone browser is *not*
--- mobile by this test: it reports "Web" and uses the web backends.
--- @return boolean
local function isMobile()
  return MOBILE[getOS()] == true
end

--- True on macOS, Windows and Linux, where subprocesses and love.thread exist.
--- @return boolean
local function isDesktop()
  return DESKTOP[getOS()] == true
end

return {
  getOS = getOS,
  isWeb = isWeb,
  isMobile = isMobile,
  isDesktop = isDesktop
}

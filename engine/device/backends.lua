--- Chooses the device backend for the platform and guarantees its shape.
---
--- Backends are loaded with pcall, the way engine/Game.lua loads the MCP
--- bridge, because a backend may legitimately not exist in a build: the desktop
--- one needs subprocesses, the web one needs the page bridge, the mobile one
--- needs a native module compiled into LÖVE. Anything that fails to load, and
--- any function a backend leaves out, falls back to
--- engine/device/backends/null.lua, so an absent or half-finished backend
--- reports `isAvailable() == false` instead of erroring at the call site.
---
--- Read engine/device/backends/null.lua for the contract a backend implements.

local system = require "engine.utils.system"
local null = require "engine.device.backends.null"

local backends = {}

local BY_OS = {
  Web = "web",
  ["OS X"] = "desktop",
  Windows = "desktop",
  Linux = "desktop",
  Android = "mobile",
  iOS = "mobile",
}

local KNOWN = { null = true, mock = true, web = true, desktop = true, mobile = true }

local SECTIONS = { "filePicker", "camera" }

local current = nil

local function warn(message)
  print("[device] " .. message)
end

-- Copies the null implementation over anything the backend does not provide, so
-- every call site can assume the whole contract is present.
local function fillGaps(backend)
  local filled = { name = backend.name or "unnamed" }
  for _, section in ipairs(SECTIONS) do
    local from = backend[section] or {}
    local fallback = null[section]
    local into = {}
    for key, value in pairs(fallback) do
      into[key] = value
    end
    for key, value in pairs(from) do
      if type(value) == "function" then
        into[key] = value
      end
    end
    filled[section] = into
  end
  return filled
end

local function load(name)
  if name == "null" then return fillGaps(null) end
  local ok, backend = pcall(require, "engine.device.backends." .. name)
  if not ok or type(backend) ~= "table" then
    warn("backend '" .. name .. "' unavailable; device features are disabled")
    return fillGaps(null)
  end
  return fillGaps(backend)
end

--- Selects the backend. Called once by Game:load before scenes are registered.
--- Safe to call again (hot reload re-runs Game:load).
---
--- The SPOOKI_DEVICE_BACKEND environment variable wins over the config, so a
--- real backend can be driven from the examples catalogue, which otherwise
--- forces "mock":
--- ```sh
--- SPOOKI_DEVICE_BACKEND=desktop love . --example device/file-picker
--- ```
--- Nothing in the test suite sets it, so CI is unaffected.
--- @param name string|nil Force a backend by name ("mock" in the examples
--- suite); nil picks from the OS.
function backends.init(name)
  local override = os.getenv("SPOOKI_DEVICE_BACKEND")
  if override and override ~= "" then
    assert(KNOWN[override], "SPOOKI_DEVICE_BACKEND must be one of null, mock, web, desktop, mobile")
    current = load(override)
    return
  end
  if name ~= nil then
    assert(type(name) == "string" and KNOWN[name],
      "device: backend must be one of null, mock, web, desktop, mobile")
    current = load(name)
    return
  end
  current = load(BY_OS[system.getOS()] or "null")
end

--- The active backend, with every contract function guaranteed present.
--- Initialises from the OS on first use so game code that requires the device
--- modules without a Game still works.
--- @return table
function backends.get()
  if not current then
    backends.init(nil)
  end
  return current
end

--- Name of the active backend, for logging and for the examples' assertions.
--- @return string
function backends.getName()
  return backends.get().name
end

return backends

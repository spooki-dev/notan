--- Opening and saving images when Notan runs in a browser.
---
--- The desktop paths in app/imageIO.lua both assume things the web build does
--- not have: an OS file picker to shell out to (no `io.popen`, no threads) and
--- somewhere on disk to write the study next to its source. So on web the page
--- around the canvas does the file handling and this module is the wire between
--- the two. Both directions are deliberately dumb: a polled file one way,
--- printed lines the other, because love.js gives Lua no way to call JS and
--- gives the page only `FS_createDataFile` and `Module.print`.
---
--- Page to app: the page writes the bytes into INBOX .. "/" .. name, then
--- writes the path into INBOX .. "/request". `poll` picks it up on the next
--- frame and the file is read back with plain `io.open`, exactly as a dropped
--- file is on desktop.
---
--- App to page (see scripts/notan-harness/index.html in the site repo):
---   [notan-web] pick                 show the file picker, please
---   [notan-web] save <name> <blocks> a PNG follows as <blocks> data lines
---   [notan-web] data <base64>        one block, 3072 bytes of PNG
---   [notan-web] done                 the PNG is complete; hand it to the user
local webBridge = {}

--- Directory the page writes incoming files into. Emscripten's in-memory
--- filesystem, so it costs nothing and vanishes with the tab.
local INBOX = "/notan-in"
local REQUEST = INBOX .. "/request"

--- Bytes per data line. A multiple of 3 so each block encodes to whole base64
--- quads and only the last block can carry padding; 3072 keeps the printed
--- lines at 4096 characters, which is small enough not to stall the console.
local BLOCK = 3072

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

-- Character per 6-bit value, looked up rather than re-sliced per byte: export
-- runs over megabytes of PNG and this is the inner loop.
local CHAR = {}
for i = 0, 63 do CHAR[i] = B64:sub(i + 1, i + 1) end

--- Base64 for one block of bytes. Padding is only correct for the final block,
--- which is why `save` is the only caller and feeds the blocks in order.
---@param s string
---@return string
local function encodeBlock(s)
  local out = {}
  local n = #s
  local i = 1
  while i + 2 <= n do
    local a, b, c = s:byte(i, i + 2)
    out[#out + 1] = CHAR[math.floor(a / 4)]
      .. CHAR[(a % 4) * 16 + math.floor(b / 16)]
      .. CHAR[(b % 16) * 4 + math.floor(c / 64)]
      .. CHAR[c % 64]
    i = i + 3
  end
  local rest = n - i + 1
  if rest == 1 then
    local a = s:byte(i)
    out[#out + 1] = CHAR[math.floor(a / 4)] .. CHAR[(a % 4) * 16] .. "=="
  elseif rest == 2 then
    local a, b = s:byte(i, i + 1)
    out[#out + 1] = CHAR[math.floor(a / 4)]
      .. CHAR[(a % 4) * 16 + math.floor(b / 16)]
      .. CHAR[(b % 16) * 4] .. "="
  end
  return table.concat(out)
end

--- Reads a whole file, or nil if it is not there.
---@param path string
---@return string|nil
local function readAll(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local bytes = file:read("*a")
  file:close()
  return bytes
end

--- Asks the page to show its file picker. Browsers only open a picker while a
--- click is still fresh, so this is worth doing from a key press or an in-app
--- button but the page keeps its own Open button for when it is refused.
function webBridge.requestPicker()
  print("[notan-web] pick")
end

--- Checks whether the page has handed over a file.
---@return string|nil path Path of the new file, nil when there is nothing waiting
function webBridge.poll()
  local request = readAll(REQUEST)
  if not request then return nil end
  os.remove(REQUEST)
  local path = request:gsub("^%s+", ""):gsub("%s+$", "")
  if path == "" then return nil end
  return path
end

--- Sends a PNG to the page, which saves it the way the browser saves anything.
--- Encoding a few megabytes of base64 blocks the frame, as writing the file
--- does on desktop.
---@param imageData love.ImageData
---@param name string File name to offer, e.g. "study-notan.png"
---@return boolean ok
---@return string|nil error
function webBridge.save(imageData, name)
  local encoded, png = pcall(imageData.encode, imageData, "png")
  if not encoded then return false, "could not encode the image" end
  local bytes = png:getString()
  if #bytes == 0 then return false, "the encoded image was empty" end

  local blocks = math.ceil(#bytes / BLOCK)
  print("[notan-web] save " .. name .. " " .. blocks)
  for i = 1, blocks do
    local from = (i - 1) * BLOCK + 1
    print("[notan-web] data " .. encodeBlock(bytes:sub(from, from + BLOCK - 1)))
  end
  print("[notan-web] done")
  return true
end

return webBridge

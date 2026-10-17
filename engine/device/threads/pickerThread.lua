--- Runs the platform's native file dialog, off the main thread.
---
--- Every desktop dialog blocks for as long as the player browses, so running it
--- on the main thread would freeze the window. One thread is started per pick
--- and exits as soon as it has pushed its answer: a pick is a rare,
--- player-initiated action, so a thread per pick costs nothing and avoids the
--- stale-worker, idle-timeout and hot-reload-leak problems a persistent worker
--- would bring.
---
--- Arguments come from `thread:start(...)`, the answer goes back on the
--- `spooki.picker.res` channel as
--- `{ id, ok, path, bytes }` / `{ id, ok = false, cancelled = true }` /
--- `{ id, ok = false, err = "..." }`. The main thread only ever `pop`s that
--- channel: a `demand` there would freeze the game, which is the whole point of
--- being here.
---
--- This file is inside the .love, so scripts/lint-lua51.sh checks it: keep it
--- within the Lua 5.1 subset even though it only ever runs on LuaJIT.

require "love.thread"

local id, osName, wantsImages, prompt, maxBytes = ...

local res = love.thread.getChannel("spooki.picker.res")

local IMAGE_EXTENSIONS = "*.png *.jpg *.jpeg *.gif *.bmp *.tga *.webp"

-- Wraps a value for /bin/sh. A single quote ends the quoted run, escapes a
-- literal quote, and opens a new run.
local function shellQuote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

-- AppleScript string literal: backslash first, or it would escape the escapes.
local function appleScriptQuote(value)
  return (tostring(value):gsub("\\", "\\\\"):gsub('"', '\\"'))
end

-- PowerShell single-quoted string: doubling is the only escape.
local function powerShellQuote(value)
  return (tostring(value):gsub("'", "''"))
end

local function commandExists(name)
  local status = os.execute("command -v " .. name .. " >/dev/null 2>&1")
  return status == true or status == 0
end

local function buildCommand()
  if osName == "OS X" then
    local kind = wantsImages and ' of type {"public.image"}' or ""
    local script = 'POSIX path of (choose file' .. kind ..
      ' with prompt "' .. appleScriptQuote(prompt) .. '")'
    -- stderr is folded in so a real failure arrives as a message rather than
    -- looking identical to a cancel.
    return "osascript -e " .. shellQuote(script) .. " 2>&1"
  end

  if osName == "Windows" then
    local filter = wantsImages
      and "Images|*.png;*.jpg;*.jpeg;*.gif;*.bmp;*.tga;*.webp|All files|*.*"
      or "All files|*.*"
    -- -STA is required: the Windows Forms dialog needs a single-threaded
    -- apartment and silently fails without it.
    return 'powershell -NoProfile -STA -Command "' ..
      "Add-Type -AssemblyName System.Windows.Forms; " ..
      "$d = New-Object System.Windows.Forms.OpenFileDialog; " ..
      "$d.Filter = '" .. powerShellQuote(filter) .. "'; " ..
      "$d.Title = '" .. powerShellQuote(prompt) .. "'; " ..
      "$d.Multiselect = $false; " ..
      "if ($d.ShowDialog() -eq 'OK') { Write-Output $d.FileName }" ..
      '" 2>&1'
  end

  if commandExists("zenity") then
    local filter = wantsImages
      and (" --file-filter=" .. shellQuote("Images | " .. IMAGE_EXTENSIONS))
      or ""
    return "zenity --file-selection --title=" .. shellQuote(prompt) .. filter .. " 2>/dev/null"
  end
  if commandExists("kdialog") then
    local filter = wantsImages and (" " .. shellQuote(IMAGE_EXTENSIONS)) or ""
    return "kdialog --getopenfilename ." .. filter .. " --title " .. shellQuote(prompt) .. " 2>/dev/null"
  end
  return nil, "no file dialog found (install zenity or kdialog)"
end

local function looksLikeAPath(text)
  return text:sub(1, 1) == "/" or text:match("^%a:[\\/]") ~= nil
end

local function runDialog()
  local command, err = buildCommand()
  if not command then
    return { ok = false, err = err }
  end

  local handle = io.popen(command, "r")
  if not handle then
    return { ok = false, err = "could not run the file dialog" }
  end
  local output = handle:read("*a") or ""
  handle:close()
  output = output:gsub("^%s+", ""):gsub("%s+$", "")

  if output == "" then
    return { ok = false, cancelled = true }
  end
  -- osascript reports a dismissed dialog as an error on stderr; so does
  -- kdialog in some builds. Neither is a failure.
  if output:lower():find("canceled", 1, true) or output:lower():find("cancelled", 1, true) then
    return { ok = false, cancelled = true }
  end
  if not looksLikeAPath(output) then
    return { ok = false, err = output }
  end
  return { ok = true, path = output }
end

-- Reading happens here rather than on the main thread: a large file would be a
-- visible hitch, and the size is checked before the read so an enormous one
-- never crosses the channel at all.
local function readFile(path)
  local file = io.open(path, "rb")
  if not file then
    return nil, "could not open " .. path
  end
  local size = file:seek("end")
  if maxBytes and size and size > maxBytes then
    file:close()
    return nil, string.format("the file is %d bytes, over the %d byte limit", size, maxBytes)
  end
  file:seek("set")
  local bytes = file:read("*a")
  file:close()
  if not bytes then
    return nil, "could not read " .. path
  end
  return bytes
end

local result = runDialog()
if result.ok then
  local bytes, err = readFile(result.path)
  if bytes then
    result.bytes = bytes
  else
    result = { ok = false, err = err }
  end
end
result.id = id
res:push(result)

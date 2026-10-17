--- Reading and writing images anywhere on disk.
---
--- LOVE's own filesystem is sandboxed to the game folder and the save
--- directory, which is no use for an app that opens the user's pictures. So
--- files come in as bytes read with plain Lua `io` and are handed to
--- `love.image` as FileData; files go out the same way. Dropped files and
--- files picked from a dialog both collapse to one path string, so there is
--- only one load path to get right.
---
--- The picker itself is the host OS's own dialog, shelled out to: LOVE has no
--- file dialog, and a hand-drawn file browser is a lot of app to maintain for
--- something every platform already does better. That command blocks until
--- the dialog closes, so it runs on a thread (see app/dialogThread.lua) and
--- the caller polls for the answer.
local imageIO = {}

--- Shell-quotes a string for a single-quoted POSIX shell argument.
---@param s string
---@return string
local function shellQuote(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

--- Everything before the last path separator.
---@param path string
---@return string
function imageIO.dirname(path)
  return path:match("^(.*)[/\\][^/\\]*$") or "."
end

--- The file name without its directory.
---@param path string
---@return string
function imageIO.basename(path)
  return path:match("[^/\\]+$") or path
end

--- The file name without its directory or extension.
---@param path string
---@return string
function imageIO.stem(path)
  local base = imageIO.basename(path)
  return base:match("^(.*)%.[^.]+$") or base
end

--- Name of the channel the picker thread answers on.
local DIALOG_CHANNEL = "notan.dialog.result"

-- Held only so a running picker thread is not collected mid-dialog.
local dialogThread = nil

--- The shell command that shows this platform's file picker and prints the
--- chosen path, or nil where there is no picker to shell out to.
---@param prompt string Dialog title
---@return string|nil
local function openCommand(prompt)
  local os_ = love.system.getOS()

  if os_ == "OS X" then
    -- AppleScript errors (including Cancel) are swallowed so a cancelled
    -- dialog is an empty result rather than a non-zero exit and stderr noise.
    return table.concat({
      "osascript",
      "-e", shellQuote("try"),
      "-e", shellQuote('POSIX path of (choose file with prompt "' .. prompt
        .. '" of type {"public.image"})'),
      "-e", shellQuote("on error"),
      "-e", shellQuote('return ""'),
      "-e", shellQuote("end try"),
      "2>/dev/null",
    }, " ")
  elseif os_ == "Linux" then
    -- Either picker may be absent; whichever runs prints a path or nothing.
    return "zenity --file-selection --title=" .. shellQuote(prompt)
      .. " 2>/dev/null || kdialog --getopenfilename . 2>/dev/null"
  elseif os_ == "Windows" then
    local script = "Add-Type -AssemblyName System.Windows.Forms;"
      .. "$d = New-Object System.Windows.Forms.OpenFileDialog;"
      .. "$d.Filter = 'Images|*.png;*.jpg;*.jpeg;*.bmp;*.tga|All files|*.*';"
      .. "if ($d.ShowDialog() -eq 'OK') { $d.FileName }"
    return 'powershell -NoProfile -STA -Command "' .. script .. '"'
  end

  return nil
end

--- Opens the host OS's file picker without blocking. The answer arrives from
--- `pollOpenDialog`; a second request while one is open is ignored.
---@param prompt string|nil Dialog title
---@return boolean started
function imageIO.requestOpenDialog(prompt)
  if dialogThread and dialogThread:isRunning() then return false end
  local command = openCommand(prompt or "Open an image")
  if not command then return false end
  dialogThread = love.thread.newThread("app/dialogThread.lua")
  dialogThread:start(command, DIALOG_CHANNEL)
  return true
end

--- Checks whether the picker has answered. Call once a frame while a request
--- is outstanding.
---@return boolean finished Whether the dialog has closed
---@return string|nil path The chosen path, nil if it was cancelled
---@return string|nil error Set when the picker thread died without answering
function imageIO.pollOpenDialog()
  local answer = love.thread.getChannel(DIALOG_CHANNEL):pop()
  if answer == nil then
    -- A thread that has stopped running without pushing crashed. Reporting it
    -- as a finished dialog matters more than the error itself: the caller is
    -- otherwise left waiting for a message that will never arrive.
    if dialogThread and not dialogThread:isRunning() then
      local err = dialogThread:getError()
      dialogThread = nil
      return true, nil, err or "the file picker stopped unexpectedly"
    end
    return false
  end
  dialogThread = nil
  answer = answer:gsub("^%s+", ""):gsub("%s+$", "")
  if answer == "" then return true end
  return true, answer
end

--- Loads an image from an absolute path on disk.
---@param path string
---@return love.ImageData|nil imageData
---@return string|nil error
function imageIO.load(path)
  local file, openErr = io.open(path, "rb")
  if not file then
    return nil, "could not open " .. imageIO.basename(path) .. ": " .. tostring(openErr)
  end
  local bytes = file:read("*a")
  file:close()
  if not bytes or #bytes == 0 then
    return nil, imageIO.basename(path) .. " is empty"
  end

  -- The name matters: love.image picks its decoder from the extension.
  local ok, fileData = pcall(love.filesystem.newFileData, bytes, imageIO.basename(path))
  if not ok then
    return nil, "could not read " .. imageIO.basename(path)
  end
  local decoded, imageData = pcall(love.image.newImageData, fileData)
  if not decoded then
    return nil, imageIO.basename(path) .. " is not an image LOVE can decode"
  end
  return imageData
end

--- Loads an image from a file dragged onto the window.
---@param file love.File LOVE's DroppedFile
---@return love.ImageData|nil imageData
---@return string|nil error
---@return string|nil path Absolute path of the dropped file
function imageIO.loadDropped(file)
  local path = file.getFilename and file:getFilename() or nil
  if path then
    local imageData, err = imageIO.load(path)
    if imageData then return imageData, nil, path end
    return nil, err, path
  end

  -- No path (shouldn't happen on desktop): fall back to LOVE's own handle.
  local opened = pcall(file.open, file, "r")
  if not opened then return nil, "could not open the dropped file", nil end
  local ok, imageData = pcall(love.image.newImageData, file)
  file:close()
  if not ok then return nil, "that file is not an image LOVE can decode", nil end
  return imageData, nil, nil
end

--- Writes ImageData to a PNG anywhere on disk.
---@param imageData love.ImageData
---@param path string Absolute destination path
---@return boolean ok
---@return string|nil error
function imageIO.savePng(imageData, path)
  local ok, encoded = pcall(imageData.encode, imageData, "png")
  if not ok then
    return false, "could not encode the image"
  end
  local file, openErr = io.open(path, "wb")
  if not file then
    return false, "could not write " .. imageIO.basename(path) .. ": " .. tostring(openErr)
  end
  file:write(encoded:getString())
  file:close()
  return true
end

return imageIO

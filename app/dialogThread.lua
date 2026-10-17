--- Runs one OS file-picker command off the main thread.
---
--- `io.popen` blocks until the dialog is dismissed, which on the main thread
--- freezes drawing: the window goes white or stops repainting for as long as
--- the picker is open. One short-lived thread per request keeps the app
--- drawing, and the thread ends as soon as it has pushed its answer, so
--- nothing is left waiting at quit.
---
--- Started as: thread:start(command, channelName)
local command, channelName = ...

require("love.thread")

local output = ""
local pipe = io.popen(command, "r")
if pipe then
  output = pipe:read("*a") or ""
  pipe:close()
end

love.thread.getChannel(channelName):push(output)

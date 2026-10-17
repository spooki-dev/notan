local inputMap = require "engine.input.inputMap"

local sceneManager = {}
local currentScene = nil
local scenes = {}
local sceneFunctions = {}

--- Instantiate a scene from its constructor, register it under its name and run its load().
--- @param sceneFunc function Scene constructor (not an instance)
--- @return Scene The new scene instance
function sceneManager.addScene(sceneFunc)
  local scene = sceneFunc()
  scenes[scene.name] = scene
  sceneFunctions[scene.name] = sceneFunc
  if scene.load then
    scene:load()
  end
  return scene
end

--- Get a registered scene instance by name
--- @param name string Scene name
--- @return Scene|nil
function sceneManager.getScene(name)
  return scenes[name]
end

--- Get the constructor a scene was registered with
--- @param name string Scene name
--- @return function|nil
function sceneManager.getSceneConstructor(name)
  return sceneFunctions[name]
end

function sceneManager.getCurrentScene()
  return currentScene
end

--- Get the current scene object
--- @return Scene|nil
function sceneManager.getCurrentSceneObject()
  if currentScene then
    return scenes[currentScene]
  end
  return nil
end

--- Set the current scene
--- @param scene string The name of the scene to set as current
--- @throws if the scene does not exist or is already the currentScene
function sceneManager.setCurrentScene(scene)
  print("Setting current scene to: " .. scene)
  -- Reset mouse cursor when changing scenes
  if love and love.mouse and love.mouse.setCursor then
    love.mouse.setCursor()
  end
  if currentScene == scene then
    error("Scene " .. scene .. " is already the current scene.")
  end
  if scenes[scene] then
    currentScene = scene
    -- The press that triggered the switch must not also fire in the new scene.
    inputMap.flushEdges()
    if not scenes[scene].loaded then
      sceneManager.checkAndCallSceneFunction("handleLoad")
      scenes[scene].loaded = true
    end
    -- Call start on the scene when it becomes current
    if scenes[scene].start then
      scenes[scene]:start()
    end
  else
    error("Invalid scene: " .. scene)
  end
end

function sceneManager.checkAndCallSceneFunction(func, ...)
  -- Check if the current scene is set
  local scene = scenes[currentScene]
  -- Call the function if it exists in the current scene, passing in it's self and the other arguments
  if scene and scene[func] then
    return scene[func](scene, ...)
  end
end

function sceneManager.click(x, y, button, istouch, presses)
  sceneManager.checkAndCallSceneFunction("handleClick", x, y, button, istouch, presses)
end

function sceneManager.load()
  sceneManager.checkAndCallSceneFunction("handleLoad")
end

function sceneManager.update(dt)
  sceneManager.checkAndCallSceneFunction("handleUpdate", dt)
end

function sceneManager.draw()
  sceneManager.checkAndCallSceneFunction("handleDraw")
end

function sceneManager.keypressed(key, scancode, isrepeat)
  local scene = scenes[currentScene]
  if scene and scene.keypressed then
    scene:keypressed(key, scancode, isrepeat)
  end
end

function sceneManager.keyreleased(key, scancode)
  local scene = scenes[currentScene]
  if scene and scene.keyreleased then
    scene:keyreleased(key, scancode)
  end
end

--- An input action went down this frame (see engine/input/inputMap.lua).
--- @param name string Action name
function sceneManager.actionPressed(name)
  sceneManager.checkAndCallSceneFunction("actionPressed", name)
end

--- An input action went up this frame.
--- @param name string Action name
function sceneManager.actionReleased(name)
  sceneManager.checkAndCallSceneFunction("actionReleased", name)
end

function sceneManager.mouseMoved(x, y)
  local scene = scenes[currentScene]
  if scene then
    scene:handleMouseMove(x, y)
  end
end

function sceneManager.mousePressed(x, y, button, istouch, presses)
  local scene = scenes[currentScene]

  if scene then
    scene:handleMouseDown(x, y, button, istouch, presses)
  end
end

function sceneManager.wheelMoved(x, y)
  local scene = scenes[currentScene]
  if scene and scene.handleScroll then
    scene:handleScroll(x, y)
  end
end

--- A finger touched the screen this frame. `id` identifies the touch across
--- move/release so multiple simultaneous touches (e.g. steer + throttle) can
--- be tracked independently; forwarded only if the current scene defines it.
function sceneManager.touchPressed(id, x, y, dx, dy, pressure)
  sceneManager.checkAndCallSceneFunction("touchpressed", id, x, y, dx, dy, pressure)
end

--- A tracked touch moved this frame. See touchPressed.
function sceneManager.touchMoved(id, x, y, dx, dy, pressure)
  sceneManager.checkAndCallSceneFunction("touchmoved", id, x, y, dx, dy, pressure)
end

--- A tracked touch lifted this frame. See touchPressed.
function sceneManager.touchReleased(id, x, y, dx, dy, pressure)
  sceneManager.checkAndCallSceneFunction("touchreleased", id, x, y, dx, dy, pressure)
end

--- Reset and reload a scene by name
function sceneManager.resetScene(name)
  local scene = scenes[name]
  if not scene then
    error("Invalid scene: " .. tostring(name))
  end

  scenes[name] = nil
  return sceneManager.addScene(sceneFunctions[name])
end

return sceneManager

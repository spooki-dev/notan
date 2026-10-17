local Object = require "engine.lib.classic"
local Camera = require "engine.Camera"
local tableUtils = require "engine.utils.table"

---@class Scene : Object
---@field name string Name of the scene
---@field backgroundColor table Background color of the scene
---@field camera Camera The scene Camera
---@field gameObjects table<string, GameObject>
---@field update function Update lifecycle method
---@field draw function Draw lifecycle method
---@field layers table<string, {zIndex: number, objects: table<string, GameObject>}>
---@field layerOrder table<{name: string, zIndex: number}>
---@field loaded boolean Whether the scene has been loaded
---@field rigidBodies table<GameObject, boolean> Track all rigid body GameObjects
---@field collisionMap table|nil Optional static geometry: anything with isRectBlocked(x, y, w, h); rigid bodies refuse moves into it
---@field hitHurtBoxObjects table<string, GameObject> Track all game objects with hit/hurt box component
---@field mouseOverGameObjects table<string, GameObject> Track all game objects with mouseover events
---@field clickGameObjects table<string, GameObject> Track all gameObjects with a click event
---@field addLayer function Add a layer to the sceneManager
---@field addGameObjectToLayer function Add a game object to a layer
---@field addGameObject function Add a game object to the scene
---@field getGameObject function Get a game object by name
---@field handleLoad function Handle loading resources for the scene
---@field handleUpdate function Handle updating the scene
---@field handleDraw function Handle drawing the scene
---@field onKeyPressed function Handle key pressed events
---@field onQuit function|nil Optional hook called by Game:quit on the current scene (autosave here)
---@field removeGameObject function Remove a game object from the scene
---@field destroyGameObject function Destroy a game object by reference or name
local Scene = Object.extend(Object)
function Scene:new(name)
  self.name = name
  self.camera = Camera()
  self.gameObjects = {}
  self.mouseOverGameObjects = {}
  self.clickGameObjects = {}
  self.scrollGameObjects = {}
  self.keyGameObjects = {}    -- objects defining onKeyPressed
  self.actionGameObjects = {} -- objects defining onActionPressed / onActionReleased
  self.layers = {}
  self.layerOrder = {}
  self.loaded = false
  self.rigidBodies = {}
  self.active = true                    -- disable to prevent drawing of child objects
  self.backgroundColor = { 0, 0, 0, 1 } -- Default background color (black)

  -- Track all game objects with hit/hurt box component
  self.hitHurtBoxObjects = {}

  -- LightManager (default nil, can be set by scene)
  self.lightManager = nil

  self:addDefaultLayers()
end

function Scene:start()
  -- Call start on all game objects
  for name, gameObject in pairs(self.gameObjects) do
    if gameObject.start then
      gameObject:start()
    end
  end
  -- Custom scene start logic (override in subclass if needed)
  -- Override this method in a subclass for custom behavior
end

function Scene:addLayer(layerName, zIndex)
  self.layers[layerName] = {
    zIndex = zIndex,
    objects = {}
  }

  -- Rebuild the layer order array
  self:rebuildLayerOrder()
end

function Scene:rebuildLayerOrder()
  self.layerOrder = {}

  -- Collect all layers
  for name, layer in pairs(self.layers) do
    table.insert(self.layerOrder, { name = name, zIndex = layer.zIndex })
  end

  -- Sort layers by zIndex
  table.sort(self.layerOrder, function(a, b)
    return a.zIndex < b.zIndex
  end)
end

function Scene:addGameObjectToLayer(gameObject)
  local layerName = gameObject.layer or "entities"
  if not self.layers[layerName] then
    error("Layer " .. layerName .. " does not exist.")
  end

  -- Ensure that a game object with the same name does not already exist in the layer
  if self.layers[layerName].objects[gameObject.name] then
    error("Game object with name " .. gameObject.name .. " already exists in layer "
      .. layerName .. ".")
  end
  self.layers[layerName].objects[gameObject.name] = gameObject
end

function Scene:addGameObject(gameObject)
  if not gameObject then
    error("attempted to add nil GameObject to scene " .. self.name)
  end
  if not gameObject.name then
    error("GameObject must have a name to be added to the scene.")
  end
  self.gameObjects[gameObject.name] = gameObject
  self:addGameObjectToLayer(gameObject)
  gameObject.scene = self
  if gameObject.parent == nil then
    gameObject.parent = self
  end

  -- If the object has hit/hurt box methods, add to hitHurtBoxObjects
  if gameObject.getHitbox or gameObject.getHurtbox then
    self.hitHurtBoxObjects[gameObject.name] = gameObject
  end
  if gameObject.onMouseOver or gameObject.onMouseEntered or gameObject.onMouseExit then
    self.mouseOverGameObjects[gameObject.name] = gameObject
  end
  if gameObject.onClick then
    self.clickGameObjects[gameObject.name] = gameObject
  end

  if gameObject.handleScroll then
    self.scrollGameObjects[gameObject.name] = gameObject
  end
  if gameObject.onKeyPressed then
    self.keyGameObjects[gameObject.name] = gameObject
  end
  if gameObject.onActionPressed or gameObject.onActionReleased then
    self.actionGameObjects[gameObject.name] = gameObject
  end

  gameObject:handleLoad()


  return gameObject
end

function Scene:getGameObject(name)
  return self.gameObjects[name]
end

function Scene:getObjectsByClass(classRef)
  local objects = {}
  for _, obj in pairs(self.gameObjects) do
    if obj.is and obj:is(classRef) then
      table.insert(objects, obj)
    end
  end
  return objects
end

function Scene:handleLoad()
  -- Load resources specific to the scene
  for name, gameObject in pairs(self.gameObjects) do
    gameObject:handleLoad()
  end
end

function Scene:handleUpdate(dt)
  if self.update then
    self:update(dt)
  end
  if self.camera and self.camera.update then
    self.camera:update(dt)
  end
  -- handleUpdate all game objects
  for name, gameObject in pairs(self.gameObjects) do
    gameObject:handleUpdate(dt)
  end
  -- Update lighting manager if present
  if self.lightManager and self.lightManager.update then
    self.lightManager:update(dt)
  end
end

function Scene:handleDraw()
  self.camera:set()

  love.graphics.setBackgroundColor(unpack(self.backgroundColor))

  if self.draw then
    self:draw()
  end
  local cameraBounds = self.camera:getBounds()
  -- Draw all game objects except 'ui' layer
  for _, layer in ipairs(self.layerOrder) do
    local layerName = layer.name
    if layerName ~= "ui" then
      local objects = self.layers[layerName].objects
      local objectsInView = {}
      for name, object in pairs(objects) do
        local pos = object.getPos and object:getPos() or object:getPos()
        local objectIsInCameraView = pos.x + object.width > cameraBounds.left and
            pos.x < cameraBounds.right and
            pos.y + object.height >= cameraBounds.top and
            pos.y < cameraBounds.bottom
        if objectIsInCameraView then
          table.insert(objectsInView, object)
        end
      end
      table.sort(objectsInView, function(a, b)
        local ay = (a.getPos and a:getPos().y or a:getPos().y) + (a.ysortOffset or 0)
        local by = (b.getPos and b:getPos().y or b:getPos().y) + (b.ysortOffset or 0)
        if ay == by then
          local ap = a.drawPriority or 0
          local bp = b.drawPriority or 0
          if ap == bp then
            -- Final tie-break on the (unique) name so draw order is stable between
            -- frames and runs; table.sort and pairs give no such guarantee.
            return a.name < b.name
          end
          return ap < bp
        end
        return ay < by
      end)
      for _, object in pairs(objectsInView) do
        object:handleDraw()
      end
    end
  end
  -- Draw lighting overlay last (on top of everything)
  if self.lightManager then
    self.lightManager:draw()
  end
  self.camera:unset()
  -- Draw all game objects in the 'ui' layer after camera unset
  local uiLayer = self.layers["ui"]
  if uiLayer then
    local uiObjects = uiLayer.objects
    local uiObjectsSorted = {}
    for name, object in pairs(uiObjects) do
      table.insert(uiObjectsSorted, object)
    end
    table.sort(uiObjectsSorted, function(a, b)
      local ap = a.drawPriority or 0
      local bp = b.drawPriority or 0
      if ap == bp then
        return a.name < b.name
      end
      return ap < bp
    end)
    for _, object in ipairs(uiObjectsSorted) do
      object:handleDraw()
    end
  end
end

---Remove a GameObject from the scene (all tables/layers/rigidBodies)
---@param gameObject GameObject
function Scene:removeGameObject(gameObject)
  -- Remove from gameObjects table
  if gameObject.name and self.gameObjects[gameObject.name] == gameObject then
    self.gameObjects[gameObject.name] = nil
  end
  -- Remove from all layers
  for _, layer in pairs(self.layers) do
    if layer.objects[gameObject.name] == gameObject then
      layer.objects[gameObject.name] = nil
    end
  end
  -- Remove from rigidBodies
  if self.rigidBodies and self.rigidBodies[gameObject] then
    self.rigidBodies[gameObject] = nil
  end
  -- Remove from hitHurtBoxObjects
  if self.hitHurtBoxObjects and gameObject.name and self.hitHurtBoxObjects[gameObject.name] == gameObject then
    self.hitHurtBoxObjects[gameObject.name] = nil
  end

  if self.mouseOverGameObjects and gameObject.name and self.mouseOverGameObjects[gameObject.name] == gameObject then
    self.mouseOverGameObjects[gameObject.name] = nil
  end

  if self.clickGameObjects and gameObject.name and self.clickGameObjects[gameObject.name] == gameObject then
    self.clickGameObjects[gameObject.name] = nil
  end

  if self.scrollGameObjects and gameObject.name and self.scrollGameObjects[gameObject.name] == gameObject then
    self.scrollGameObjects[gameObject.name] = nil
  end

  if self.keyGameObjects and gameObject.name and self.keyGameObjects[gameObject.name] == gameObject then
    self.keyGameObjects[gameObject.name] = nil
  end

  if self.actionGameObjects and gameObject.name and self.actionGameObjects[gameObject.name] == gameObject then
    self.actionGameObjects[gameObject.name] = nil
  end
end

---Remove a GameObject and every descendant it put in the scene.
---
---`GameObject:addGameObject` registers a child with the scene as well as with
---its parent, so taking a composite object out one object at a time leaves its
---children behind: still drawn, still answering input, and still holding their
---names, which turns the next attempt to build the same thing into a duplicate
---name error. Anything assembled from nested objects -- a UICanvas and its
---boxes, say -- should come out through here.
---@param gameObject GameObject
function Scene:removeGameObjectTree(gameObject)
  if not gameObject then return end
  local children = gameObject.gameObjects
  if type(children) == "table" then
    for i = #children, 1, -1 do
      self:removeGameObjectTree(children[i])
    end
  end
  self:removeGameObject(gameObject)
end

---Destroy a GameObject by reference or name
---@param gameObjectOrName GameObject|string
function Scene:destroyGameObject(gameObjectOrName)
  local obj = gameObjectOrName
  if type(gameObjectOrName) == "string" then
    obj = self:getGameObject(gameObjectOrName)
  end

  if obj ~= nil and type(obj) ~= "string" and obj.destroy then
    obj:destroy()
  end
end

-- Pass keypressed event to the scene hook and to objects that define onKeyPressed.
-- Prefer actions (onActionPressed) over raw keys so bindings stay remappable.
function Scene:keypressed(key, scancode, isrepeat)
  if self.onKeyPressed then
    self:onKeyPressed(key, scancode, isrepeat)
  end
  for name, gameObject in pairs(self.keyGameObjects) do
    if gameObject.active then
      gameObject:onKeyPressed(key, scancode, isrepeat)
    end
  end
end

function Scene:keyreleased(key, scancode)
  if self.onKeyReleased then
    self:onKeyReleased(key, scancode)
  end
end

--- An input action (engine/input/inputMap.lua) went down this frame. Calls the
--- optional scene hook `onActionPressed(name)` then every active object that
--- defines `onActionPressed`.
--- @param name string Action name
function Scene:actionPressed(name)
  if self.onActionPressed then
    self:onActionPressed(name)
  end
  for _, gameObject in pairs(self.actionGameObjects) do
    if gameObject.active and gameObject.onActionPressed then
      gameObject:onActionPressed(name)
    end
  end
end

--- An input action went up this frame. See actionPressed.
--- @param name string Action name
function Scene:actionReleased(name)
  if self.onActionReleased then
    self:onActionReleased(name)
  end
  for _, gameObject in pairs(self.actionGameObjects) do
    if gameObject.active and gameObject.onActionReleased then
      gameObject:onActionReleased(name)
    end
  end
end

function Scene:handleMouseMove(x, y)
  for name, gameObject in pairs(self.mouseOverGameObjects) do
    gameObject:handleMouseOver(x, y)
  end
end

function Scene:handleClick(x, y)
  for name, gameObject in pairs(self.clickGameObjects) do
    gameObject:handleClick(x, y)
  end
end

function Scene:handleMouseDown(x, y, button, istouch, presses)
  for name, gameObject in pairs(self.mouseOverGameObjects) do
    if gameObject.handleMouseDown and gameObject.active then
      gameObject:handleMouseDown(x, y, button, istouch, presses)
    end
  end
end

function Scene:handleScroll(x, y)
  for name, gameObject in pairs(self.scrollGameObjects) do
    if gameObject.handleScroll and gameObject.active then
      gameObject:handleScroll(x, y)
    end
  end
end

-- function Scene:reset()
--   -- Remove all game objects
--   for name, gameObject in pairs(self.gameObjects) do
--     if gameObject.destroy then
--       gameObject:destroy()
--     end
--   end
--   self.gameObjects = {}
--   -- Clear layers and recreate defaults
--   self.layers = {}
--   self.layerOrder = {}
--   self:addDefaultLayers()
--   -- Reset camera
--   self.camera = Camera()
--   -- Clear rigidBodies and hitHurtBoxObjects
--   self.rigidBodies = {}
--   self.hitHurtBoxObjects = {}
--   -- Reset lightManager
--   self.lightManager = nil
--   -- Mark as not loaded
--   self.loaded = false
-- end

---Add default layers to the scene
function Scene:addDefaultLayers()
  self:addLayer("ground", 1)
  self:addLayer("entities", 2)
  self:addLayer("ui", 3)
end

return Scene

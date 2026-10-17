local Scene = require "engine.Scene"
local colors = require "constants.colors"
local Vector4 = require "engine.Vector4"
local UICanvas = require "engine.ui.UICanvas"
local UIBox = require "engine.ui.UIBox"
local UIText = require "engine.ui.UIText"
local Button = require "engine.ui.Button"
local FocusGroup = require "engine.ui.FocusGroup"
local InputPrompt = require "engine.ui.InputPrompt"
local sceneManager = require "engine.sceneManager"

---@class Menu : Scene
local Menu = Scene.extend(Scene)

function Menu:new()
  Menu.super.new(self, "Menu")
  self.backgroundColor = colors.black
  self.focus = FocusGroup()
end

function Menu:load()
  local startButton = Button("Start", "Start")

  function startButton:onClick()
    sceneManager.setCurrentScene("Game")
  end

  local controlsButton = Button("Controls", "Controls")

  function controlsButton:onClick()
    sceneManager.setCurrentScene("Controls")
  end

  -- Arrow keys / d-pad / left stick move between the buttons, Enter / A activates.
  self.focus:clear()
  self.focus:add(startButton):add(controlsButton)

  self:addGameObject(UICanvas("MenuUI", {
    UIBox("MenuContainer", {
      UIBox("MenuSpacer", {}, {
        height = 150,
      }),
      UIBox("MenuContent", {
        UIText("MenuTitle", "NOTAN", {
          font = "header",
          textAlign = "center",
          color = colors.vec4Yellow,
        }),
        UIText("MenuSubtitle", "Built with spooki-love", {
          textAlign = "center",
          color = colors.vec4Grey,
        }),
        UIBox("MenuButtonRow", {
          UIBox("MenuButtonContainer", {
            startButton,
            controlsButton,
          }, {
            width = "40%",
            gap = 10,
          }),
        }, {
          display = "flex",
          flexDirection = "row",
          justifyContent = "center",
          margin = Vector4(40, 0, 0, 0),
        }),
        UIBox("MenuHintRow", {
          UIBox("MenuHints", {
            InputPrompt("MenuHintMove", { "ui_up", "ui_down" }, "Navigate", { color = colors.vec4Grey }),
            InputPrompt("MenuHintAccept", "ui_accept", "Select", { color = colors.vec4Grey }),
          }, {
            width = "40%",
            display = "flex",
            flexDirection = "row",
            gap = 10,
            height = 32,
          }),
        }, {
          display = "flex",
          flexDirection = "row",
          justifyContent = "center",
          margin = Vector4(30, 0, 0, 0),
        }),
      }, {}),
    }, {
      padding = Vector4(10, 10, 10, 10),
    }),
  }, {
    padding = Vector4(10, 10, 10, 10),
  }))
end

function Menu:start()
  if not self.focus:getFocused() then
    self.focus:setFocus(1)
  end
end

function Menu:update(dt)
  self.focus:update(dt)
end

return Menu

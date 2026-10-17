---
title: UI
description: The flexbox-style UI primitives under engine/ui, their constructors, style keys, layout rules and the font and cursor contracts they rely on.
order: 4
---

The UI system is a small hand-rolled layout engine built on `GameObject`. Every primitive lives in `engine/ui/` and is a `GameObject` subclass, so UI trees are added to a scene with `self:addGameObject(...)` like anything else. Layout is driven by a `styles` table on each box, with a subset of CSS flexbox semantics: block stacking by default, a single flex row when asked for, percentage or fixed widths, padding, margin, gap and absolute positioning. This page documents what the source actually supports; see `scenes.md` for where UI is built in a scene's lifecycle and `game-objects.md` for the `GameObject` base.

## Primitives

Require each primitive by its dotted module path.

| Module | Require | Role |
|---|---|---|
| `engine/ui/UICanvas.lua` | `require "engine.ui.UICanvas"` | Root container. Sized to the window (or `styles.width`/`height`) and stacks its children vertically. |
| `engine/ui/UIBox.lua` | `require "engine.ui.UIBox"` | The general box. Block or flex-row layout, padding, border, background, hover styles. Everything else extends it. |
| `engine/ui/UIStack.lua` | `require "engine.ui.UIStack"` | A `UIBox` that forces `display = "flex"` and `flexDirection = "row"`. |
| `engine/ui/UIText.lua` | `require "engine.ui.UIText"` | Wrapped text drawn with a cached font. Height comes from the wrapped line count. |
| `engine/ui/Button.lua` | `require "engine.ui.Button"` | Clickable, focusable box with a centred `UIText` label, border highlight and cursor switching. |
| `engine/ui/UIBar.lua` | `require "engine.ui.UIBar"` | Labelled progress bar: a header row (title and value) over a `BarFill`. |
| `engine/ui/BarFill.lua` | `require "engine.ui.BarFill"` | The coloured fill inside a `UIBar`. Green, yellow or red by percentage. |
| `engine/ui/InputPrompt.lua` | `require "engine.ui.InputPrompt"` | Draws the glyph for an input action on the active device plus a label. No children, fixed height. |
| `engine/ui/FocusGroup.lua` | `require "engine.ui.FocusGroup"` | Not a GameObject. Keyboard and gamepad navigation over focusable items such as `Button`. |

## Building a tree

The convention is one `UICanvas` root per screen, `UIBox` or `UIStack` containers for rows and columns, and leaf components inside them, all passed through the `children` array. Children are positioned by their parent, so you never set positions on UI objects yourself. `scenes/Menu.lua` is the worked example; this is the shape of it with the hint row removed:

```lua
local UICanvas = require "engine.ui.UICanvas"
local UIBox = require "engine.ui.UIBox"
local UIText = require "engine.ui.UIText"
local Button = require "engine.ui.Button"
local Vector4 = require "engine.Vector4"
local colors = require "constants.colors"

function Menu:load()
  local startButton = Button("Start", "Start")
  function startButton:onClick()
    sceneManager.setCurrentScene("Game")
  end

  self:addGameObject(UICanvas("MenuUI", {
    UIBox("MenuContainer", {
      UIBox("MenuSpacer", {}, { height = 150 }),
      UIBox("MenuContent", {
        UIText("MenuTitle", "NEW GAME", {
          font = "header", textAlign = "center", color = colors.vec4Yellow,
        }),
        UIBox("MenuButtonRow", {
          UIBox("MenuButtonContainer", { startButton }, { width = "40%", gap = 10 }),
        }, {
          display = "flex", flexDirection = "row", justifyContent = "center",
          margin = Vector4(40, 0, 0, 0),
        }),
      }, {}),
    }, { padding = Vector4(10, 10, 10, 10) }),
  }, { padding = Vector4(10, 10, 10, 10) }))
end
```

Every object in the tree is registered with the scene by name, so names must be unique within the scene (duplicates throw, including on hot reload). Attach behaviour by defining `onClick` on the instance before it is added, as above.

## Constructors

Signatures are quoted from the source. `name` is always the scene-unique object name.

| Constructor | Notes |
|---|---|
| `UIBox:new(name, children, styles, debugOptions)` | `children` and `styles` default to `{}`. `debugOptions` is the debug table below. |
| `UICanvas:new(name, children, styles)` | Width and height come from `styles.width`/`styles.height`, otherwise the window size at construction. Honours `padding` only. |
| `UIStack:new(name, children, styles, options)` | Writes `styles.display` and `styles.flexDirection` into the table you pass, so `styles` must be a table, not `nil`. |
| `UIText:new(name, children, styles)` | The second parameter is the text string despite being named `children`. `styles` is required (it reads `styles.font`, default `"body"`, and `styles.color`, default white). |
| `Button:new(name, label, styles)` | Registers the box as `name .. "Button"` with a child `UIText` named `name .. "Title"`. `styles` is optional: `height` (50), `font` (`"small"`), `color`, `highlightColor`, `width`, `margin`, `padding`. |
| `UIBar:new(name, title, value, width, height)` | `width` is a percentage integer (50 for 50%), `height` the fill height in pixels (default 10). The box is named `name .. "Container"`. |
| `BarFill:new(name, width, height)` | Named `name .. "BarFill"`. Created by `UIBar`; rarely used directly. |
| `InputPrompt:new(name, actions, label, styles)` | `actions` is one action name or an ordered list. Styles: `scale`, `font`, `color`/`labelColor`, `keycapColor`, `keycapTextColor`, `showAll`, `device`, `gap`, `width`, `height`. |
| `FocusGroup:new(opts)` | `opts` is `{ columns = 1, wrap = true, horizontal = false }`. Call `group:update(dt)` from the scene's `update`. |

`Button` also provides `setLabel(label)`, `setHighlighted(on)`, and the `FocusGroup` contract `focus()`, `blur()`, `activate()`. `InputPrompt` provides `setLabel(label)` and `setActions(actions)`. Changing a label does not re-run layout.

## Styles reference

These are the keys `engine/ui/UIBox.lua`, `UICanvas.lua` and `UIText.lua` read. Anything else in a `styles` table is ignored.

| Key | Type | Meaning |
|---|---|---|
| `display` | `"block"`, `"flex"`, `"none"` | `"block"` (default) stacks children vertically. `"flex"` is only implemented together with `flexDirection = "row"`. `"none"` sets the object inactive at load. |
| `flexDirection` | `"row"` | The only direction implemented. `UIStack` sets it for you. |
| `gap` | number | Pixels between children, in both block stacks and flex rows. |
| `justifyContent` | `"center"` | Centres a flex row's children horizontally. Other values have no effect. |
| `alignItems` | `"center"` | Centres flex-row children vertically, but only when the box has a `height`. |
| `position` | `"absolute"` | Positions the child at the parent's origin plus `left`/`top` and removes it from the flow. With no `width` and a `right`, width is `parent.width - (right - left)`; likewise `height` from `bottom`. |
| `left`, `top`, `right`, `bottom` | number | Offsets for `position = "absolute"`. `left`/`top` default to 0. |
| `width` | number or `"NN%"` | A number is used as-is. A percentage is resolved against the parent's inner width (or the row width minus gaps in a flex row). Omitted: fill the parent, or an equal share of a flex row. |
| `height` | number | Fixed height. Omitted: the sum of child heights (block) or the tallest child (flex row). |
| `zIndex` | number | Draw priority within the `ui` layer. Default is the parent's priority plus one. |
| `background` or `fillColor` | `Vector4` | Fill colour. `background` wins when both are set. |
| `border` | `Vector4` | Border thickness per side. Default `Vector4(0, 0, 0, 0)` draws nothing. |
| `borderColor` | `Vector4` | Border colour. White if a border is set without one. |
| `padding` | `Vector4` | Inset applied to children and added to the drawn height. |
| `margin` | `Vector4` | Space around the child inside its parent's stacking. |
| `hover` | table | `{ background = Vector4, borderColor = Vector4 }`, applied while the mouse is over the box. |
| `font` | string | `UIText` only. A `cacheManager` font key, default `"body"`. |
| `color` | `Vector4` | `UIText` only. Text colour, default `Vector4(1, 1, 1, 1)`. |
| `textAlign` | `"left"`, `"center"`, `"right"` | `UIText` only. Default `"left"`. |

## Vector4 ordering

`padding`, `border` and `margin` are `Vector4(top, right, bottom, left)`, read by the engine as `.x`, `.y`, `.z`, `.w` in that order. It is not a rectangle: do not pass `(left, top, right, bottom)` or `(x, y, width, height)` style values.

```lua
-- 20px above, 10px on each side, nothing below
UIBox("Panel", children, { padding = Vector4(20, 10, 0, 10) })
```

`Vector4:new(x, y, z, w)` defaults every component to 0, so `Vector4(8)` is 8px on top only.

## Hover styles

`UIBox` defines `onMouseEntered` and `onMouseExit`, so every box is registered for mouse-over dispatch. On enter it copies `styles.hover.background` into `fillColor` and `styles.hover.borderColor` into `borderColor`; on exit it restores the base `background`/`fillColor` and `borderColor`. `Button` builds on this: its base `hover.borderColor` is the `highlightColor`, and it also recolours the label and switches the cursor.

## Hiding with display = "none"

Setting `display = "none"` makes `UIBox:load` set `active = false`, which stops drawing and all mouse and key handlers for that object. It is read at load time only; to hide at runtime use `object:toggleActive(false, true)` from `GameObject`, which also disables children. Hidden boxes still occupy their slot in layout.

## UIBar

`UIBar(name, title, value, width, height)` builds this tree, all registered under the scene:

- `name .. "Container"` (the bar itself)
  - `name .. "Header"`: `name .. "Label"` (the title, font `small`) and `name .. "ValueText"` (right-aligned, font `small`)
  - `name .. "BarContainer"`: `name .. "BarFill"`

Update it with `UIBar:updateValue(newWidth, newLabel)`, where `newWidth` is again a percentage integer and `newLabel` the value text. `BarFill:update` recomputes its pixel width from the parent each frame and picks red at 33% or below, yellow at 66% or below, otherwise green.

```lua
local health = UIBar("Health", "HP", "100 / 100", 100, 12)
-- later
health:updateValue(45, "45 / 100")
```

## Debug options

The fourth `UIBox` argument is a table of flags. They are drawn by `engine/renderer.lua` with colours matching browser devtools.

| Flag | Shows |
|---|---|
| `debugBox` | The content box (inside padding), blue. |
| `debugPadding` | Padding bands, green. |
| `debugMargin` | Margin bands outside the box, orange. |
| `debugGap` | Gap bands between children, purple. |

```lua
UIBox("Row", children, { gap = 10, padding = Vector4(4, 4, 4, 4) },
  { debugBox = true, debugPadding = true, debugGap = true })
```

## Fonts and cursors

Fonts are looked up by key through `cacheManager.getFont`, which errors on a missing key, and `UIText:new` looks its font up at construction time. The keys the UI modules use are:

| Key | Used by |
|---|---|
| `body` | `UIText` default |
| `small` | `Button` label, `UIBar` label and value, `InputPrompt` default |
| `header`, `subheader` | Game scenes (Menu uses `header`); preloaded alongside the others |

`scenes/Preload.lua` preloads all four from LOVE's built-in default font (a `nil` path) and is registered first in `main.lua` because `sceneManager.addScene` runs `load()` immediately, so any scene that builds UI in `load()` needs the fonts cached before it is registered. See `assets.md#fonts`.

`Button` calls `cursorManager.setCursor("active")` on mouse enter and `cursorManager.setCursor("default")` on exit. `setCursor` errors on an unknown key, so a game that uses `Button` must define both `default` and `active` in the `cursors` block of the `Game` config (see `engine.md`).

## How layout is computed

Layout runs once, when the tree is added to the scene. `Scene:addGameObject` calls `handleLoad`, which calls `UIBox:load`:

1. The box sizes itself from its parent: a percentage `width` against the parent's width minus horizontal padding, a number as-is, otherwise the parent's inner width. Flex-row parents set the child's width instead and mark it `isFlexChild`.
2. Each child is positioned (block stacking or flex row) and added with `self:addGameObject(child)`, which loads the child and recurses.
3. `UIBox:recalculateHeight` sums child heights (plus margins, padding and gaps) or takes the tallest in a row, or uses `styles.height` plus vertical padding. It then calls the parent's `recalculateHeight` and `recalculateChildPos`, so heights bubble up and positions are fixed from the top down.

`UIText:recalculateHeight` measures `font:getWrap(text, width)` and multiplies by the font height, so text height depends on the width it was given. Because widths flow down from the parent at load time, a box only lays out correctly if its parent already has a width: deep nesting beyond a canvas, a container and one flex row needs checking with the debug flags. Nothing re-runs layout when the window is resized; `UICanvas` takes the window size at construction and `Game:resize` only resizes the post-processing canvases.

## Layers and the camera

`UIBox` and `UICanvas` set `self.layer = 'ui'` in their constructors. `Scene:handleDraw` draws every other layer inside `camera:set()`/`camera:unset()`, Y-sorted and culled to the camera bounds, then draws the `ui` layer after `unset`, sorted by `drawPriority` only, with no culling. UI therefore lives in screen space, which is also the space mouse events arrive in, so hover and click hit-testing works without any camera conversion. To put a box in world space, set `object.layer = "ground"` or `"entities"` before adding it to the scene. See `scenes.md` for the layer model.

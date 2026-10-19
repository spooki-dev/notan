# Changelog

## 2026-10-20

- New application icon: a landscape cut down to three flat values — light sky, mid peak, dark peak — instead of the framed wordmark inherited from the template. It is the thing the app does to a photograph, and unlike lettering it still reads at the 16 pixels a dock or a browser tab actually draws. The window, dock and taskbar now show it too, rather than falling back to the LÖVE heart.

- Fixed the macOS and Windows builds failing on startup with `module 'engine.device.backends' not found`. The packaging step matched its exclude list loosely, so the rule meant to drop the dev-only `engine/dev/` folder took `engine/device/` with it — the file picker, the camera and every other device backend — and the released app could not open an image, or start at all.

## 2026-10-19

- Added cropping to a canvas ratio: type the dimensions of the panel you are painting on into the Crop section, and a box locked to that ratio appears over the photo. Drag it to frame the shot or a corner to resize it, `K` toggles it, `0` fits the crop rather than the whole image, the grid divides the crop, and the export is the box. The dimensions are remembered between sessions; the box resets with each new photo.

## 2026-10-15

- Added a composition grid: a Grid section in the panel with vertical and horizontal line counts, `G` to toggle it, drawn over the image at any zoom and burned into the export.

- Scaffolded from [spooki-love](https://github.com/spooki-dev/spooki-love) (40ed39e).

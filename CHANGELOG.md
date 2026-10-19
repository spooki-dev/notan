# Changelog

## 2026-10-20

- Releases now come as a macOS `.dmg` and a Windows installer instead of zip files. The disk image opens with the app next to an Applications folder, so installing is the drag you expect, and the Windows installer puts the game and its libraries somewhere sensible with a Start-menu shortcut and a proper entry in Settings → Apps. It installs for one user and never asks for admin rights.

- Fixed the macOS and Windows builds failing on startup with `module 'engine.device.backends' not found`. The packaging step matched its exclude list loosely, so the rule meant to drop the dev-only `engine/dev/` folder took `engine/device/` with it — the file picker, the camera and every other device backend — and the released app could not open an image, or start at all.

## 2026-10-19

- Added cropping to a canvas ratio: type the dimensions of the panel you are painting on into the Crop section, and a box locked to that ratio appears over the photo. Drag it to frame the shot or a corner to resize it, `K` toggles it, `0` fits the crop rather than the whole image, the grid divides the crop, and the export is the box. The dimensions are remembered between sessions; the box resets with each new photo.

## 2026-10-15

- Added a composition grid: a Grid section in the panel with vertical and horizontal line counts, `G` to toggle it, drawn over the image at any zoom and burned into the export.

- Scaffolded from [spooki-love](https://github.com/spooki-dev/spooki-love) (40ed39e).

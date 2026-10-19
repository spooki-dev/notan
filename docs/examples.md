---
title: Examples
description: The runnable examples catalogue, how to run and test it, and how to add an example.
order: 11
---

The `examples/` directory holds small scenes that each show one part of the engine, browsable at [/spooki-love/examples](/spooki-love/examples) where every example runs in the browser next to its source. The same files are the engine's regression suite: each runs with a fixed timestep, scripted input, its own assertions and a golden screenshot, so a change under `engine/` that breaks behaviour fails `scripts/test.sh`.

## Running examples

```sh
love . --examples                      # picker: browse and open any example
love . --example camera/follow         # run one example with hot reload
```

In the picker the arrow keys, d-pad or stick move, Enter or A opens an example and Escape quits. Inside an example Escape returns to the picker.

## Testing

```sh
scripts/test.sh                        # lint + every example
scripts/test.sh camera ui/buttons      # categories and/or example ids
scripts/test.sh --update-snapshots     # rewrite the golden screenshots
```

The script runs `scripts/lint-lua51.sh` first, then `love . --test`. Every example is driven for 120 frames at dt = 1/60 with its scripted input, its `check` function runs after each frame, and the last frame is compared with `examples/__snapshots__/<category>/<slug>.png` within a small tolerance. Exit status is 0 when everything passes, 1 on failures and 2 on a harness error; failures leave `.actual.png` and `.diff.png` images in `examples/.test-output/`.

`.github/workflows/ci.yml` runs the same suite on every push and pull request using LÖVE under Xvfb, and can regenerate the goldens from a manual dispatch.

## Adding an example

1. Create `examples/<category>/<slug>.lua` in an existing category (or add a line to `examples/categories.lua` for a new one).
2. Start the file with the header the catalogue and the website read:

   ```lua
   -- title: Follow target
   -- description: One sentence shown under the title.
   -- order: 1
   -- tags: camera, followTarget
   ```

3. Return a `Scene` subclass named after the id (`"camera/follow"`). Use the shared actions (`move_*`, `action`, `secondary`, `pause`) and the preloaded fonts and sheets; never preload assets or bind Escape.
4. Optionally add `Example.script` (scripted input), `Example.check(scene, ctx)` (assertions) and `Example.shaders` (post-processing). Draw deterministically so the screenshot is stable.
5. Run `scripts/test.sh --update-snapshots <category>/<slug>` to write the golden, then `scripts/test.sh` to confirm it passes, and commit both.

The full conventions, harness fields and tolerance rules are in `examples/README.md`.

# Docs

These pages are published at https://spookidev.com/spooki-love/docs. The site pulls `docs/*.md` from `main` at build time, so a push that touches this folder updates the published docs.

## Writing a page

- Every file needs YAML frontmatter with `title`, a one-sentence `description` and a numeric `order`. The site renders `title` as the page heading, so do not put an H1 in the body.
- File names are the URL slugs: lowercase letters, digits and hyphens, ending in `.md`. This `README.md` is skipped.
- Link between pages with the bare filename, optionally with an anchor: `scenes.md#layers`.
- Link to source files with repo-root paths such as `engine/Scene.lua` or `scripts/release.sh`. The site rewrites them to GitHub.
- Tag code fences with `lua` or `sh`.

## Pages

| Order | File | Covers |
| --- | --- | --- |
| 1 | `getting-started.md` | What the template is, scaffolding with `init.sh`, running, directory map |
| 2 | `scenes.md` | Scene lifecycle, registration, layers, camera |
| 3 | `game-objects.md` | GameObject class, lifecycle hooks, events, children |
| 4 | `ui.md` | UI primitives, styles, contracts |
| 5 | `input.md` | Actions, bindings, prompts and rebinding |
| 6 | `engine.md` | `Game` config, engine modules, contracts, state and saves |
| 7 | `assets.md` | Preloading, fonts, cursors, audio, marketing art export |
| 8 | `build-and-release.md` | Lua 5.1 rules, `release.sh`, itch.io checklist |
| 9 | `code-signing.md` | Apple Developer ID and notarization, Windows Authenticode, the signing hooks in `release.sh` |
| 10 | `development.md` | Hot reload, MCP bridge, debugging, conventions |
| 11 | `examples.md` | The examples catalogue: running, testing, adding an example |

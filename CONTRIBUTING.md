# Contributing

Thanks for taking a look. This is a small single file Hammerspoon config, so contributing is pretty low ceremony.

## Setup

1. Install [Hammerspoon](https://www.hammerspoon.org).
2. Point Hammerspoon at your checkout, or copy `init.lua` into `~/.hammerspoon/` while you work on it.
3. Edit, then reload from the Hammerspoon menu (the config also auto reloads when you save a `.lua` file).

## Workflow

1. Branch off `main`.
2. Make your change. Keep it focused, one idea per pull request is easier to review.
3. If behavior changes, add a line to `CHANGELOG.md` under "Unreleased".
4. Open a pull request and fill in the template.

## Style

- Plain Lua, no build step, no dependencies beyond Hammerspoon.
- Match the existing two space indentation and the section comment headers.
- Prefer small helper functions with clear names.
- If you touch the slider panel HTML, keep it self contained inside `init.lua`.

## Testing by hand

There is no automated test suite. Before opening a pull request, sanity check the things you touched:

- Toggle the camera (open Photo Booth or join a quick call) and confirm the chosen screen lights up and then restores.
- Open the slider panel and drag both sliders, confirm the preview is smooth and Done and Cancel both behave.
- Reload the config and confirm there are no errors in the Hammerspoon console.

A quick syntax check without running anything:

```sh
hs -c "local f,e=loadfile(os.getenv('HOME')..'/.hammerspoon/init.lua'); return f and 'ok' or e"
```

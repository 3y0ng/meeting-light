# TODO (follow-up PRs)

Ideas for future work, roughly in priority order. Each is meant to be its own pull request so it stays easy to review.

## Distribute as a Hammerspoon Spoon
Package the code as `MeetingLight.spoon` so installing does not overwrite anyone's existing `~/.hammerspoon/init.lua`. Users would just `hs.loadSpoon("MeetingLight")` and start it. This is the biggest usability win and the main reason to do it as its own PR, since it is a real refactor.

## Demo GIF in the README
A short clip showing the chosen screen lighting up when the camera turns on, plus the slider panel updating live. Drop it near the top of the README under the panel screenshot.

## External monitor brightness boost (DDC)
Optional feature: when the fill light turns on, push the external monitor to full backlight brightness over DDC (using something like `m1ddc`), then restore the previous brightness when the call ends. Needs a check that the monitor actually accepts DDC, and a menu toggle to turn the boost on or off.

## luacheck in CI
Add a `.luacheckrc` and a GitHub Actions workflow that runs luacheck on pull requests. Confirm the file is warning clean first so the build is green from day one.

## Rename internal `white*` terms to `fill*`
The light is tinted now, so `whiteDisplays` and "Auto-white during meetings" are a little misleading. Rename internally to `fill*` and update the menu wording, with a small migration so existing `meeting_light_settings.lua` files still load.

## Smaller ideas
- Brightness floor so the slider cannot go uselessly dim.
- A keyboard shortcut to open the slider panel.
- Optional "cover the whole screen" mode (overlay instead of wallpaper) for a stronger, more even light.
- Remember a few favorite warmth and brightness presets in the menu.

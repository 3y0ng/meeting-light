# Changelog

All notable changes to this project are noted here. The format is loosely based on
Keep a Changelog, and the project aims to follow semantic versioning.

## [Unreleased]

### Changed
- Menu bar icon is now a monochrome template bulb (white in a dark menu bar, dark in a light one) instead of an emoji. Three states: outline (on and waiting), filled (camera live), slashed (paused). Falls back to the emoji icons if the image can't be built.

### Added
- A `CONFIG` block at the top of `init.lua` for default warmth, default brightness, and the slider ranges. The slider panel reads its min and max from here.
- `CONTRIBUTING.md`, a pull request template, and this changelog.

### Removed
- Two unused path variables, so the file stays lint clean.

## [0.1.0]

### Added
- Auto fill light on the chosen screens while the camera is in use (Zoom, Teams, Google Meet, including in a browser).
- Wallpaper is saved before lighting and restored when the camera turns off.
- Menu bar control to pause the feature and pick which displays get lit.
- Slider panel for warmth and brightness with a smooth live preview.
- Settings persist and the script starts on login.

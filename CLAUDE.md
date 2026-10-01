# Takedown Racer — notes for Claude / contributors

Arcade crash racer in **Godot 4.7.2**, GDScript only. Target: 60 fps at 720p–900p on integrated GPUs.
Never use the word "Burnout" or any of its names/assets anywhere in the game or repo content.

## Layout
- `scenes/`   .tscn scenes (main.tscn = entry point)
- `scripts/`  GDScript; one class per file, `snake_case.gd`, `class_name` in PascalCase
- `assets/`   imported content: `cars/<ID>/` (.glb + textures), `tracks/<name>/`, `audio/` (.ogg)
- `tools/`    offline converters (Python 3, stdlib only where possible) and `check.sh`
- `tests/`    headless smoke test (`smoke_test.gd`); add new playable scenes to its SCENES list
- `docs/`     design notes, SR3 survey
- `LICENSES/` full licence texts; every imported asset gets a line in `CREDITS.md`

## Conventions
- Default renderer: Compatibility (`gl_compatibility`). Forward+/Mobile only via settings.
- Physics: Jolt, 60 Hz. Units: metres, kg, seconds. +Y up, car forward = -Z (Godot convention).
- Tabs for indentation, static typing (`var x: float`) everywhere.
- Tunables are `@export` vars so they can be tweaked in the inspector.
- Keep the FPS/frame-time overlay (`scripts/perf_overlay.gd`) in every playable scene.
- No SSR/SDFGI/volumetric fog by default; pooled particles; LODs/visibility ranges on meshes.

## Licensing
Project is GPL-3.0 (tracks and car sim parameters come from Stunt Rally 3, GPL-3.0).
Before importing any asset: check its licence, skip if unclear, record it in `CREDITS.md`.

## Verify
`tools/check.sh` — imports the project headless and runs the smoke test; must print `CHECK PASSED`.
Set `GODOT=` to your Godot 4.7.2 binary if it isn't on PATH.

## Progress
See `PROGRESS.md` (update it with every milestone).

# Progress

- [x] M0 Setup — Godot 4.7.2 skeleton, Compatibility renderer, Jolt physics, headless check (`tools/check.sh`).
- [x] M1 Drive — LK4 car converted from SR3 (.mesh → .glb via `tools/sr3_car_to_glb.py`), raycast-wheel arcade
  physics (`scripts/arcade_car.gd`), slip-angle drift, boost button + meter (drift fills it), chase cam with
  speed FOV + radial motion blur, engine sound, FPS overlay (F3), test loop road (`scenes/test_drive.tscn`).
- [x] M2 Track — `tools/sr3_track_convert.py` converts an SR3 track (heightmap + road spline + scene) into
  terrain heights/splat, road.glb (with guard rails on elevated sections), checkpoints, racing line,
  vegetation (licence-cleared trees only), sky. `scripts/track_builder.gd` builds it at load;
  `race_manager.gd` = checkpoints/laps/timing/respawn-on-line; HUD shows lap/time/best/countdown.
  `scenes/race.tscn` (main scene) = Atm2-RedOakPark, 3 laps. AI test driver laps it in ~53 s
  (`tests/race_capture.gd`).
- [ ] M3 Traffic
- [ ] M4 Crashes
- [ ] M5 Rivals + takedowns
- [ ] M6 Crash Mode
- [ ] M7 Polish

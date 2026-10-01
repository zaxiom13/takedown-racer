# Stunt Rally 3 survey (what we take, where it lives, licences)

Repos read: `stuntrally/stuntrally3` (code + data), `stuntrally/tracks3` (tracks), `stuntrally/blendfiles` (source .blend files).

## 1. Car physics — where it lives
`stuntrally3/src/vdrift/` (VDrift-derived, GPL-3.0):
| File | What |
|---|---|
| `cardynamics_simulate.cpp`, `cardynamics_update.cpp` | per-tick integration: suspension → tyre forces → drivetrain, rigid body via Bullet |
| `cartire.cpp` | Pacejka "Magic Formula" tyre (lateral a0–a13, longitudinal b0–b10, aligning c0–c17) |
| `carsuspension.cpp` | spring/damper (bounce/rebound), travel, anti-roll |
| `carengine.cpp`, `cartransmission.cpp`, `cardifferential.cpp`, `carclutch.cpp` | torque curve, gears, final drive, anti-slip diff |
| `cardynamics_load.cpp` | reads `.car` files |
| `crashdetection.cpp` | impact detection from velocity change (useful idea for M4) |

Per-car tuning data: `data/carsim/{easy,normal,hard}/cars/<ID>.car` (INI-like: mass, torque curve, gear ratios,
final drive, spring/damper rates, travel, tyre radius, steering max-angle, rot_drag), `tires/*.tire` (Pacejka coeffs),
`susp/*.susp`, `surfaces.cfg` (friction per surface).

**Plan:** we do NOT port the Pacejka sim. The arcade car (raycast wheels on a RigidBody3D) reads a few numbers from
the `.car` file — mass, wheelbase/track from wheel positions, tyre radius, spring/damper rates, travel, max steer angle,
torque-curve peak, gear ratios → top speed — and replaces the tyre model with a tunable grip curve + drift state.
These are parameters/ideas, not ported code.

## 2. Mesh / asset formats
- Car & prop meshes: Ogre-Next binary `.mesh` (`[MeshSerializer_v2.1 R2]`), textures `.png`/`.jpg`, materials in `.material.json`.
- Godot can't read `.mesh`. Blender isn't needed: `tools/ogre_mesh_to_glb.py` (our own stdlib-Python reader for the
  v2.1 chunk format) writes `.glb` directly, so the conversion is reproducible headless. The `.blend` sources in
  `blendfiles` exist, but the shipped `.mesh` files are the in-game, already-UV'd/textured versions.
- Sounds: `.wav` → convert to `.ogg` (needs ffmpeg/oggenc at conversion time).

## 3. Track format (`tracks3/<Track>/`)
| File | Content |
|---|---|
| `heightmap.f32` | raw little-endian float32 heights, N×N (e.g. 512×512 = 1 MiB). `heightmap2.f32` = optional 2nd (horizon) terrain |
| `scene.xml` | `<terrain triangle=…>` grid spacing (m), `<start pos rot>` (quaternion), sky, fog, light, vegetation layers, objects |
| `road.xml` | `<P pos w aT mtr onTer chkR a ar …>` control points of a closed Hermite spline (Catmull-Rom tangents, see `src/road/SplineBase.cpp`); `onTer=1` → y comes from terrain; `w` = width; `chkR` > 0 marks a checkpoint (radius × width); `ar` bank angle |

Converter plan (M2): Python reads the three files → generates terrain mesh + road ribbon mesh + checkpoint list →
writes a Godot `.tscn` + `.res`/`.glb`. Coordinate note: SR3/Ogre is also +Y up, so axes map 1:1 (to be verified on a real track).

## 4. Licences of what we plan to use
| Asset | Licence | Use? |
|---|---|---|
| SR3 code (`src/`) | GPL-3.0 | ideas/params only |
| SR3 tracks (`tracks3`, all) | GPL-3.0 (`tracks3/License.txt`) | yes — project is GPL-3.0 |
| Car **LK4** (body, glass, wheel, textures) | CC0 (clarabox, blendswap 18708) | **yes — first car (M1)** |
| Cars OT, R1, R2, R3 | CC0 | candidates for traffic/rivals |
| Cars 3B, BE, HI, MO, SX, Q1, Q3, H1 | CC-BY 4.0 | yes, with attribution |
| Cars BV, HR, LF, SZ, TU, O | CC-BY (version unstated → treat as CC-BY 4.0, attribute) | yes, with attribution |
| Cars ES, FN, FR4, S8 | CC-BY-SA | ok (share-alike compatible with GPL-3 via CC-BY-SA 4.0 one-way; for 3.0 keep asset under its own licence) |
| Engine sounds `sounds/engines/*` | CC-BY-4.0 (CryHam) | yes |
| Hit/crash sounds | per-file freesound CC-BY/CC0 listed in `_sounds.txt`, `_crash.txt` | per file, check each |
| Road textures | per-file in `textures/road/_road*.txt` (CC0 / CC-BY 3.0 / "from VDrift", "from Ogre") | only CC0/CC-BY entries; skip "from VDrift/Ogre" unless traced |
| Skies | ambientCG / Poly Haven (CC0); some hdrmaps.com (own licence) | CC0 ones only |
| Vegetation/props | per-folder `_readme*.txt` | check per model before importing |

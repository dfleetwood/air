# Aerie — bird flight prototype

A small archipelago of floating islands you can walk on and fly between,
with a fully live atmosphere: time of day, four seasons, and wind.
Everything is generated procedurally at startup — no imported assets.

Open the folder in Godot 4.x (Forward+) and run `main.tscn`.

## Controls

| Input | Action |
| --- | --- |
| Mouse | Aim — the bird flies toward where the camera looks |
| WASD | Walk (camera-relative) |
| SPACE | Jump on ground; in air: start flying / flap for a speed boost |
| SHIFT | Air brake while flying |
| T / G | Scrub time of day forward / back |
| Y | Toggle the automatic day/night cycle |
| 1–4 | Set season (spring / summer / autumn / winter) |
| R | Respawn on the home island |
| Q | Cycle quality preset (LOW / MEDIUM / HIGH — starts on LOW) |
| ESC | Release / capture the mouse |

## Performance

The quality preset (Q) is the main lever. LOW (default) disables volumetric
fog — by far the biggest GPU cost — and drops render scale, MSAA, and shadow
range; an exponential depth haze stands in for the volumetrics. MEDIUM/HIGH
re-enable volumetric fog for laptops/desktops with a real GPU. The HUD shows
live fps.

## Flight model

Arcade glide: diving converts altitude into speed, climbing bleeds it off,
flapping adds a burst. Fly too slow and the bird stalls and sinks. White
particle columns near some islands are thermal updrafts — circle inside one
to gain altitude for free. Land by flying gently onto any upward surface.

## Changeability pipeline (the point of the prototype)

- `season`, `wind_dir`, `wind_strength` are **global shader parameters**
  (declared in `project.godot`, driven every frame from `main.gd`).
  `island.gdshader` and `leaves.gdshader` both read them — one uniform,
  the whole world changes: grass color, snow cover, foliage sway.
- Time of day rotates a single `DirectionalLight3D` under a
  `PhysicalSkyMaterial`, which handles sunrise/sunset color for free.
- Winter thickens the volumetric fog and starts snowfall; autumn spawns
  drifting leaves; wind strength/direction oscillates and physically pushes
  the bird in flight.

## Known prototype shortcuts

- Everything is flat-shaded procedural geometry — deliberate low-poly look.
- Trees keep snow-covered leaf blobs in winter instead of going bare.
- Season transitions lerp linearly (winter back to spring rewinds through
  autumn/summer rather than wrapping forward).
- No streaming/LOD yet; the whole world is a handful of small meshes.

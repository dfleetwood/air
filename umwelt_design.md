# The Island Spirit — Umwelt Design

## Working Draft — Claude's capture of the 2026-07-13 conversation

**Status:** First scaffold, written to be attacked.
**Working title:** none. `aerie` is a prototype folder name, not a title.
**Engine:** Godot 4.7, Forward+.
**Relationship to `delta/godot_sonar_umwelt_design.md`:** none, except method.
That document is a bat in a cave. This is a different game. What carries over is
the *approach* (§2), not the subject, the senses, the tone, or the architecture.

> **Health warning.** Everything below marked *[assumed]* is Claude inferring from
> the conversation, not something Darren said. The real design is currently in
> Darren's head. The sections that matter most — §8, what tending actually *is* —
> are the ones this draft is least entitled to. Overwrite freely.

---

## 1. Premise

You are a spirit tending an island.

You perceive the island through an **umwelt** — a perceptual world assembled from
sense-channels. The umwelt is not given. You construct it, subject to one
restriction:

> **It must be built from senses that real animals actually have.**

The restriction is the whole design. Without it, "construct your own perception"
collapses into arbitrary visual effects. With it, every channel arrives with a
real asymmetry, a real blindness, and a real gift — and those are the things that
make a percept feel like a percept rather than a filter.

Traversal is flight and walking; the island is one of several across an
archipelago. *[assumed — carried from the original brief: "we can walk but we
also need to fly."]*

---

## 2. The Method (the one thing inherited from the sonar work)

The sonar prototype's v2 died: a hand-rolled evidence field, tens of thousands of
raycasts a second, reinventing badly what the graphics stack already does. v3
worked because it noticed that **acoustic transport is light transport** — the
call is a shadowed spotlight at the eye, reverb is ambient, material is a BRDF —
and then spent its entire budget on the one thing no renderer gives you:

> range is exact, direction is vague.

Generalised, that is this project's central technical rule:

> **Find the rendering primitive that already computes the physics.
> Then spend everything on the single asymmetry that makes it not an eye.**

This is also the *feasibility* argument. It is not "abstraction is cheap"
(true but shallow). It is that an honestly-modelled sense usually turns out to be
something the GPU already does — and what remains, the alien part, is one shader.

---

## 3. The Inversion (this game's departure from the bat)

The sonar umwelt is a study in **deprivation**: acoustic shadow, decay, stale
memory, ambiguity, the moth that survives by holding still. It produces something
tense and claustrophobic. Correctly so — that is what being a bat is like.

This game must invert the sign. **Birds perceive more than we do, not less.**
Tetrachromacy and UV. Magnetoreception. Sky polarisation. Infrasound that hears a
storm a thousand kilometres away. Filoplumes that read airflow across the wing.
This is literal biology, not poetic licence.

Keep every bit of the sonar doc's rigour — real senses, honest asymmetries, render
the content not the channel — and point it at **abundance**. The bat umwelt is a
poverty you endure. The spirit's umwelt is a surplus you compose.

That inversion is what makes the game awe rather than dread, and it is what lets
it keep the emotional register the concept boards asked for ("calm freedom, the
joy of flying, the beauty of nature") without rendering a single photoreal wave.

**Why the spirit conceit earns the composite:** a real animal has one umwelt and
no say in it. A spirit tending an island can plausibly braid several. The freedom
would be arbitrary without the restriction; the restriction would be a cage
without the freedom. The two halves need each other.

---

## 4. Central Design Rule

Mirroring the sonar doc's "do not render objects, render the current evidence for
objects":

> **Do not render the island. Render what the spirit perceives of it.**

Corollaries:

- There is no "the island, plus a sense overlay." There is only the percept.
- A sense is not a filter applied to a scene. It is the scene.
- No HUD. If the spirit needs to know something, it must be **perceptible**.
  (See §8 — this is the load-bearing claim of the whole design.)

---

## 5. Anti-Goals

The system has failed if a player describes it as:

- an overlay, a vision mode, a "detective vision," a scanner;
- Tron, LiDAR, night vision, a wireframe, a hologram, a heat-map;
- a photographic island with effects on top;
- a HUD with the numbers turned into shapes;
- a synaesthesia toy with no spatial truth;
- **cold, clinical, or sci-fi.** Abstraction defaults to this. The animist frame
  is the counterweight and it must be fought for actively.

The last one is the real danger and it is not in the sonar doc's list, because a
bat cave is *allowed* to be cold.

---

## 6. Sense Palette

Every pillar from the concept boards has a real sense that renders it better than
a camera would. This is the core argument for the whole approach.

| Pillar (from the boards) | Sense | The asymmetry that makes it not an eye |
|---|---|---|
| **Wind** — "ride the currents" | Mechanoreception; filoplumes (feathers that exist only to sense airflow) | **No occlusion, no distance.** You feel air at the body, richest across the wings, and know nothing of the air a mile off. The world assembles around you as you move. |
| **Horizon / navigation** | Magnetoreception (cryptochrome hypothesis: birds may literally *see* it, as a modulation of vision; inclination gives latitude) | Direction without objects. A structure with no surface. |
| **Day / night** | Sky polarisation (what bees and birds actually navigate by) — plus stellar navigation, which birds genuinely do | **Strongest at dusk, when the sun is below the horizon.** Night stops being an absence and becomes a different structure. This fixes the boards' weakest pillar. |
| **Weather** | Infrasound; barometric sense (birds evacuate ahead of tornadoes days early) | You perceive the storm **before it arrives**, from enormous distance, as low structure at the edge of the world. |
| **Wildlife / life** | UV (flowers have UV nectar guides — literal landing markers; kestrels track vole trails that fluoresce); chemoreception as plumes drifting on the wind already being simulated | Reveals need, not just presence. See §8. |

Note what silently drops out of the budget: photoreal surf, volumetric
cloudscapes, dense foliage, groomed feathers. The three hardest rendering problems
on the concept boards stop existing, because they are not things the spirit
perceives.

**Scope discipline:** two gorgeous senses beat six shallow ones. Each sense is a
full render mode with its own art direction and its own legibility problem. Ship
2–3.

---

## 7. The Unsolved Problem: Fusion

Sonar is one sense, exclusive and total. It never had to solve this. **This game's
core design problem is what happens when several senses are true at once.**

How do magnetic structure, thermal bloom, scent plume, and airflow coexist in one
frame without becoming a Christmas tree?

Two bets, neither proven:

1. **Attunement is the gameplay.** The senses are not all on at once. You shift the
   mix; what you can perceive determines what you can do. The act of re-perceiving
   is the verb.
2. **Each sense owns a distinct register.** One is *structure*, one is *field*, one
   is *event*. They layer like a painting rather than competing like overlays.

The sonar doc's colour policy (§12.4 there — monochrome, luminance carries the
spatial variables, no rainbow range-mapping) matters *more* with five senses than
with one, not less.

**This section is the project's main risk. If fusion does not resolve, the game is
a beautiful soup.**

---

## 8. Tending — *THE GAP*

This is the part that is in Darren's head and nowhere else, and it is the part
everything else depends on. The claim in §4 — *no HUD, need must be perceptible* —
is only cashable if tending has real mechanics.

The attractive shape, *[assumed, and probably wrong in the specifics]*:

- Something on the island is wrong. A blighted grove, a severed current, a
  distressed animal, a season that will not turn.
- **The wrongness is only perceptible in the right sense.** You cannot see the
  blight; you smell it, or you perceive the absence of life-warmth where warmth
  should be, or you feel the current has stopped.
- So the loop is: *attune → perceive → find → tend → the island answers.*
- The sense you choose determines what you can find. That is what makes the umwelt
  a **tool** and not a **skin**, and it is the difference between a tech demo and
  a game.

**Questions only Darren can answer:**

- What does tending physically consist of? What is the verb at the moment of
  contact?
- Why does the island need tending? What are the stakes, and what happens if you
  do nothing?
- Is the spirit *bound* to one bird, or does it inhabit creatures? (The original
  brief said walk *and* fly — is walking a different body?)
- Is the umwelt composed once, like a character build, or shifted fluidly moment
  to moment? (§7's first bet assumes fluid. If it is a build, the whole game is a
  different shape.)
- Do you acquire senses over time? Earned how — and from what?
- Is there a failure state at all, or is this strictly a game of care?

---

## 9. Legibility Requirements (non-negotiable)

Whatever the percept, it must answer, at all times:

- Where is the ground?
- Where is that surface, and **can I land on it?** — harder than anything in the
  cave; touching down needs a surface known well enough to commit to.
- Where am I going, and where have I been?
- Is that thing alive?

Flight plus landing is a strictly harder legibility problem than a cave, because
you have both the 200 m vista regime and the 1.5 m standing regime, and the
percept must survive both. *(See the earlier note: landing roughly doubles
environment scope in a conventional renderer. In an umwelt renderer it is cheaper
— ground at foot height can be warmth and density rather than grass cards — but it
is not free.)*

---

## 10. What Already Exists

`res://` (this folder) — a working flight prototype, built 2026-07-13:

- Five procedural floating islands, walk + glide flight, thermal updrafts, wind
  that pushes the bird, day/night, four seasons.
- **`season` / `wind_dir` / `wind_strength` as global shader parameters** driven
  per-frame from `main.gd`. One uniform changes the whole world. This is already
  the right spine for a perceptual system: the senses read world state, they do
  not each re-derive it.
- Quality presets (Q) because the dev machine is an Intel HD 620.

It is currently rendered *conventionally* — lit surfaces, a sky, fog. Every bit of
that rendering is disposable. The **geometry, physics, wind field, and world-state
spine are the parts worth keeping**, and they are exactly the parts an umwelt
renderer needs underneath it (cf. the sonar doc's split: authoritative physical
world, separate perceptual world; the player sees only the second).

---

## 11. First Slice

One test, in the spirit of the sonar doc's first sprint. Take the prototype's
existing geometry and render **only the air sense** — the whole world, nothing
else.

Why this one:

- It is the game's core mechanic. If it works, the game works.
- It reuses the method: a vector field is something the GPU is already good at,
  and the thermals already exist in the scene as nodes with radius/base/top.
- Its asymmetry is strong and unprecedented: **no occlusion, no distance, richest
  at the wings.** It is the exact inverse of sonar's (directional, range-exact),
  which is a good sign — it means the method generalises rather than repeats.

**Success criterion:**

> Can you find and ride a thermal you cannot see, purely by perceiving the air?

Do not add a second sense until the answer is yes.

### RESULT (2026-07-13): yes.

`air.tscn`, run with `-- demo`, flies an autopilot that is told **nothing** about
where the thermal is. It samples the wind at its two wingtips and banks toward
whichever one is being lifted harder. That is all it knows — and it is exactly
what the player perceives.

    t=  2.0s  alt  35.0   60.7 m from column  (open air)
    t=  6.0s  alt  37.7    7.6 m from column  (*** IN THE CORE ***)
    t= 22.0s  alt  59.3    7.0 m from column  (*** IN THE CORE ***)
    t= 60.0s  alt  83.5   53.2 m from column  (topped out, drifting off)

**35 m to 83.5 m, sixty seconds, not one flap.** The information needed to soar is
present in the local air, so the percept is flyable. Note it tops out and leaves
near the column's ceiling, which is what a real thermal does.

What made it findable is that a thermal **draws air in** around its base, so the
air *at your own body* leans toward a column you are nowhere near. You do not spot
the thermal; you notice the medium tilting, and follow it upstream. No distant
rendering, no marker. (`INFLOW_REACH` in `island_field.gd`.)

**A real bug fell out of the measured test:** the bank sign was inverted — raising
yaw swings the nose *left*, so the bird was steering away from every thermal it
found. It was in the player's flight too. A visual check would never have caught
it; a numeric one caught it in a single run.

### What the air is made of, and how it is drawn

Three primitives were tried. The first two are dead and the code is kept only as a
record:

1. **Points** (`air.gdshader`) — a starfield. Dots are not a medium.
2. **Filaments / contours** (`air_draw.gdshader`) — streaklines as trailed tubes.
   Fluid, but it reads as *hair*: a diagram OF the wind rather than the wind.
3. **Volumetric dye** (`air_fog.gdshader`) — **this is the one.** A `FogVolume` and
   a `shader_type fog` shader: the air carries dye, and Godot raymarches it. A
   fluid is a density, not a curve. Thermal = a luminous warm column. Ground = the
   pale motionless hush against rock. Wake = torn murk. Rock = a clean hole in the
   smoke, because air cannot be there.

**Cheap fluid dynamics, without a solver.** Two tricks do nearly all the work:
- **Curl noise.** The curl of a noise field is divergence-free by construction, so
  it cannot make sources or sinks — it *has* to swirl. Layer octaves and you get
  eddies inside eddies, which is the actual signature of turbulence. It costs a
  few noise taps.
- **Advected dye.** Back-trace each sample point along the flow and read the dye
  there, so smoke stretches and shears along the streamlines instead of sitting
  still in space.

If real vortex shedding is wanted later, a Stam stable-fluids solver (advect, then
Jacobi-project) on a 64³ 3D texture via Godot compute shaders is well within a
4060. It is not needed for the percept to work — this one already flies.

**Ego-motion cancellation.** The medium is perceived in a frame carried along at
the bird's own velocity, so what you see is the air's *own* motion and not your
speed through it — a wind tunnel, where the body holds still and the fluid moves.
This is the honest percept, not a cheat: a wing subtracts its own airspeed exactly
as vision subtracts your gait. You do not perceive the rush. You perceive the wind.
It buys the ground for free, too — still air near rock *appears* still while
everything else streams, so the floor is where the world stops moving.

**Gotcha that cost an hour:** `return` is illegal inside a `fog()` processor. Godot
fails the compile and renders you *nothing*, in silence. Mask, don't return.

### Still open in the air sense

- Landing has not been tested. The boundary-layer hush should read as a floor, but
  nobody has tried to actually touch down on it yet. §9 is unproven.
- The analytic SDF ignores the collision mesh's noise displacement, so the felt
  surface and the solid surface disagree by a metre or two. Fix before landing.
- The dye is blobby at close range; froxel resolution is the limit.
- Warmth. It is currently beautiful but *cold* — a physics visualisation, not a
  sacred place. See §5: this is the anti-goal that matters most, and it is not
  solved.

---

## 12. Open Questions Beyond §8

- Does the spirit's perception have *uncertainty*, or is a spirit's percept exact?
  (The bat's uncertainty was the source of its drama. Removing it removes tension —
  keeping it may fight the "calm freedom" register. Unresolved.)
- Is there a "true" appearance of the island the player ever sees? Should there be?
  (Strong instinct: **no.** But it is a real question — an eventual reveal is a
  cheap and powerful card, and playing it would cost the entire premise.)
- Does the island perceive *you*?
- How does the umwelt render *another spirit*, or a creature that has its own?
- Warmth: what actively makes this feel sacred rather than clinical? Palette, pace,
  sound, the animist frame — but this needs a concrete answer, not a hope.

class_name IslandField
extends RefCounted

# THE FIELD — the authoritative physical world, expressed as a field.
#
# The islands are never drawn. Both the collision meshes and the air percept are
# derived from what is in here, and the bird's flight physics samples the same
# wind_at() the particles are advected by. One source of truth, three consumers.
#
# WARNING: air.gdshader contains a GLSL twin of sdf() / wind_at(). They must be
# kept in step by hand. If you change the physics here, change it there.

const ISLANDS := [
	{ "pos": Vector3(0, 0, 0), "r": 42.0 },
	{ "pos": Vector3(150, 18, 70), "r": 28.0 },
	{ "pos": Vector3(-130, 30, 150), "r": 24.0 },
	{ "pos": Vector3(55, -12, 235), "r": 34.0 },
	{ "pos": Vector3(-70, 45, -170), "r": 20.0 },
]

# x,y,z = column axis (at its base). w unused. Paired with THERMAL_P below.
const THERMALS := [
	{ "pos": Vector3(66, -20, 18), "radius": 14.0, "base": -20.0, "top": 95.0, "power": 7.5 },
	{ "pos": Vector3(188, 0, 96), "radius": 11.0, "base": 0.0, "top": 105.0, "power": 8.5 },
	{ "pos": Vector3(-162, 10, 176), "radius": 10.0, "base": 10.0, "top": 120.0, "power": 9.0 },
	{ "pos": Vector3(96, -34, 262), "radius": 13.0, "base": -34.0, "top": 80.0, "power": 7.0 },
	{ "pos": Vector3(-96, 26, -196), "radius": 9.0, "base": 26.0, "top": 130.0, "power": 9.5 },
]

# Thickness of the viscous boundary layer — the shell of slowed air that clings
# to every surface. This is the ONLY thing that makes ground perceptible, so it
# is generous: a bird's is centimetres, ours is metres.
const BOUNDARY := 9.0
const RIDGE_GAIN := 1.5
const TURB_GAIN := 0.9

# Squash factors: the islands are spheres, flattened into a dome above and
# stretched into a root below. Same numbers as the mesh builder, so the field and
# the collision agree about where the rock is.
const SQUASH_UP := 0.32
const SQUASH_DOWN := 1.35


# -- shape -------------------------------------------------------------------

# Surface point for a direction on the unit sphere — used to build collision.
static func surface(island: Dictionary, unit: Vector3, noise: FastNoiseLite) -> Vector3:
	var r: float = island["r"]
	var seed_off: Vector3 = island["pos"] * 0.05
	var rr := r * (1.0 + 0.18 * noise.get_noise_3dv(unit * 2.5 + seed_off))
	var p := unit * rr
	p.y *= SQUASH_UP if p.y >= 0.0 else SQUASH_DOWN
	return p


# Analytic distance to the nearest island. Approximate — it ignores the noise
# displacement the collision mesh has, so the felt surface and the solid surface
# disagree by a metre or two. For a percept that is tolerable; for landing it is
# the first thing to fix.
static func sdf(p: Vector3) -> float:
	var d := 1e9
	for island in ISLANDS:
		var q: Vector3 = p - island["pos"]
		q.y /= SQUASH_UP if q.y > 0.0 else SQUASH_DOWN
		d = minf(d, (q.length() - island["r"]) * SQUASH_UP)
	return d


static func grad(p: Vector3) -> Vector3:
	var e := 0.6
	var g := Vector3(
		sdf(p + Vector3(e, 0, 0)) - sdf(p - Vector3(e, 0, 0)),
		sdf(p + Vector3(0, e, 0)) - sdf(p - Vector3(0, e, 0)),
		sdf(p + Vector3(0, 0, e)) - sdf(p - Vector3(0, 0, e)))
	return g.normalized() if g.length_squared() > 1e-8 else Vector3.UP


# -- the wind ----------------------------------------------------------------

# Everything the air does, at one point. The particles are advected by the GLSL
# twin of this; the bird is pushed by this. They are the same world.
static func wind_at(p: Vector3, prevailing: Vector3) -> Vector3:
	var d := sdf(p)
	if d < 0.0:
		return Vector3.ZERO
	var n := grad(p)
	var bl := smoothstep(0.0, BOUNDARY, d)   # 0 at the surface, 1 in free air
	var near := 1.0 - bl

	var v := prevailing
	# Air cannot enter rock: near a surface, strip the component going into it.
	v -= n * v.dot(n) * near
	# Ridge lift — air driven at a windward face has nowhere to go but up.
	var speed := prevailing.length()
	if speed > 0.001:
		var windward: float = maxf((prevailing / speed).dot(-n), 0.0)
		v += Vector3.UP * windward * speed * RIDGE_GAIN * near

	v += thermal_vel(p)
	# Viscous drag: the air stops dead at the rock.
	v *= lerpf(0.06, 1.0, bl)
	return v


# A thermal is not only its column — it draws air in around its base. That inflow
# is what makes it findable without being seen: the air at your body leans toward
# it, and you follow the lean upstream. (GLSL twin in air.gdshader.)
const INFLOW_REACH := 4.0


static func thermal_vel(p: Vector3) -> Vector3:
	var v := Vector3.ZERO
	for t in THERMALS:
		var c: Vector3 = t["pos"]
		if p.y < t["base"] or p.y > t["top"]:
			continue
		var off := Vector2(p.x - c.x, p.z - c.z)
		var dxz := off.length()
		var r: float = t["radius"]
		var outer: float = r * INFLOW_REACH
		if dxz >= outer:
			continue
		var power: float = t["power"]
		var span: float = t["top"] - t["base"]
		var height: float = clampf((p.y - t["base"]) / maxf(span, 1.0), 0.0, 1.0)
		var fade: float = smoothstep(1.0, 0.65, height)
		if dxz < r:
			var core: float = 1.0 - dxz / r
			v.y += power * core * core * fade
		else:
			var f: float = 1.0 - (dxz - r) / (outer - r)
			f = f * f
			var toward := -off / maxf(dxz, 0.001)
			v.x += toward.x * power * 0.40 * f * fade
			v.z += toward.y * power * 0.40 * f * fade
			v.y += power * 0.28 * f * fade
	return v

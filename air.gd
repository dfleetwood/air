extends Node3D

# SLICE 1 — THE AIR SENSE, ALONE.
#
# The islands are here: solid, collidable, landable. They are never rendered.
# The only thing rendered is the medium — and the islands are legible entirely
# through what they do to it. Air piles up against a windward face. It goes still
# against every surface. It tumbles in a wake. It rises off a warm one. Rock is
# where air cannot be.
#
# The test, and the only thing this scene exists to answer:
#
#     Can you find and ride a thermal you cannot see, purely by perceiving air?
#
# F1 reveals the physical world. That is a debugging crutch and it is not the
# game; if the percept only works with F1 held down, the percept has failed.

const BirdScript := preload("res://bird.gd")

# Filaments, not motes. A few thousand streaklines read as wind; twenty thousand
# dots read as fog.
const QUALITY := [200, 450, 900]
const QUALITY_NAMES := ["LOW", "MEDIUM", "HIGH"]

var bird: CharacterBody3D
var particles: GPUParticles3D
var air_mat: ShaderMaterial
var fog_volume: FogVolume
var fog_mat: ShaderMaterial
var env: Environment
var hud: Label
var reveal_meshes: Array[MeshInstance3D] = []

var wind_yaw := 0.7
var wind_strength := 6.0
var quality := 1
var revealed := false
var _t := 0.0
var _spawn := Vector3.ZERO
var _noise := FastNoiseLite.new()
var _climb := 0.0

# THE TEST. Run with `-- demo` and the bird flies itself at a thermal, holding a
# straight glide. If the field is real, altitude must RISE without a single flap.
# This is how we answer the success criterion with a number instead of a hunch.
var _demo := false
var _demo_frames := 0


func _enter_tree() -> void:
	_setup_actions()


func _ready() -> void:
	_noise.seed = 1337
	_noise.frequency = 1.0
	_build_environment()
	for island in IslandField.ISLANDS:
		_build_island(island)
	_spawn_bird()
	_build_air()
	_build_hud()
	_demo = OS.get_cmdline_user_args().has("demo")
	if _demo:
		_start_demo()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	_t += delta
	# The wind breathes. It is never the same air twice.
	wind_strength = 5.0 + 1.8 * sin(_t * 0.13) + 0.9 * sin(_t * 0.47)
	wind_yaw += delta * 0.02

	if Input.is_action_just_pressed("quality"):
		quality = (quality + 1) % 3
		particles.amount = QUALITY[quality]
	if Input.is_action_just_pressed("reveal"):
		revealed = not revealed
		for m in reveal_meshes:
			m.visible = revealed
	if Input.is_action_just_pressed("respawn") or bird.global_position.y < -200.0:
		bird.reset(_spawn)

	_climb = lerpf(_climb, bird.velocity.y, minf(1.0, delta * 3.0))
	_update_air()
	_update_hud()


# Launch upwind of a thermal, aimed straight through it, wings locked. No flaps,
# no steering, no lift of its own. Any altitude gained is the air's doing.
func _start_demo() -> void:
	var t: Dictionary = IslandField.THERMALS[0]
	var c: Vector3 = t["pos"]
	var start := c + Vector3(-95.0, 55.0, 0.0)
	var dir := (c - start).normalized()
	bird.reset(start)
	bird.start_flight(atan2(-dir.x, -dir.z), 0.0, 14.0)
	print("DEMO — a bird that knows only the air at its own wings.")
	print("It is told NOTHING about where the thermal is. It banks toward whichever")
	print("wingtip is being lifted harder, and that is all. If it climbs, the percept")
	print("contains enough to fly on.\n")
	print("thermal 0 is at %s (core radius %.0f m). Launch %s, alt %.0f. No flapping.\n" % [
		c, t["radius"], start, start.y])


# On the PHYSICS clock, not the render clock — in headless the two run at wildly
# different rates and the render clock will lie about how far the bird got.
func _physics_process(_delta: float) -> void:
	if not _demo:
		return
	_demo_frames += 1
	if _demo_frames > 3600:
		get_tree().quit()
		return

	# PROPRIOCEPTION, not omniscience. Two probes, one at each wingtip, sampling
	# the only thing a bird can actually know: what the air is doing where its
	# body is. Then bank toward the lifted wing. This is gradient ascent, and it
	# is also just... soaring.
	var p := bird.global_position
	var b := Basis.from_euler(Vector3(0.0, bird.fly_yaw, 0.0))
	var right: Vector3 = b * Vector3.RIGHT
	var fwd: Vector3 = b * Vector3.FORWARD
	var probe := p + fwd * 6.0
	var lift_l := wind_at(probe - right * 13.0).y
	var lift_r := wind_at(probe + right * 13.0).y
	var lift_c := wind_at(p).y
	# Bank TOWARD the lifted wing. Note the minus: increasing yaw swings the nose
	# to the left, so turning right means yaw goes down. Getting this backwards
	# makes a bird that flees every thermal it finds, which is exactly what it did.
	# And once in lift, hold the turn in — that is what centres you in a core.
	var diff := lift_r - lift_l
	var bank: float = diff * 0.9 + signf(diff) * lift_c * 0.35
	bird.cam_yaw = bird.fly_yaw - clampf(bank, -1.5, 1.5)
	bird.cam_pitch = 0.0

	if _demo_frames % 120 != 0:
		return
	var t: Dictionary = IslandField.THERMALS[0]
	var c: Vector3 = t["pos"]
	var dxz := Vector2(p.x - c.x, p.z - c.z).length()
	var zone := "open air"
	if dxz < t["radius"]:
		zone = "*** IN THE CORE ***"
	elif dxz < t["radius"] * IslandField.INFLOW_REACH:
		zone = "in the inflow"
	print("t=%5.1fs  alt %7.1f  vy %+5.1f  | %6.1f m from column  air.y %+5.2f  (%s)" % [
		_demo_frames / 60.0, p.y, bird.velocity.y, dxz, lift_c, zone])


func prevailing() -> Vector3:
	return Vector3(cos(wind_yaw), 0.0, sin(wind_yaw)) * wind_strength


# The bird flies through the same field the particles are advected by.
func wind_at(p: Vector3) -> Vector3:
	return IslandField.wind_at(p, prevailing())


func _setup_actions() -> void:
	var defs := {
		"move_forward": KEY_W, "move_back": KEY_S,
		"move_left": KEY_A, "move_right": KEY_D,
		"flap": KEY_SPACE, "brake": KEY_SHIFT,
		"respawn": KEY_R, "quality": KEY_Q, "reveal": KEY_F1,
	}
	for a in defs:
		if InputMap.has_action(a):
			continue
		InputMap.add_action(a)
		var ev := InputEventKey.new()
		ev.physical_keycode = defs[a]
		InputMap.action_add_event(a, ev)


func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	# Not black. Black is a void, and the air is not a void — it is a medium, and
	# it is everywhere. This is the colour of air you cannot yet read.
	env.background_color = Color(0.055, 0.065, 0.085)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.6, 0.75)
	env.ambient_light_energy = 0.25
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	# Restrained. Heavy bloom turns tracers into stars, and this is a medium, not
	# a night sky.
	env.glow_enabled = true
	env.glow_intensity = 0.25
	env.glow_bloom = 0.05
	# The medium is volumetric. It is not a surface, and it is not a line — it is
	# a thickness of air between you and everything else.
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0
	env.volumetric_fog_gi_inject = 0.0
	env.volumetric_fog_length = 140.0
	env.volumetric_fog_detail_spread = 1.5
	env.volumetric_fog_ambient_inject = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


# Solid, collidable, and invisible. The physical world persists; you simply do
# not perceive it. (cf. the sonar doc's two-world split.)
func _build_island(island: Dictionary) -> void:
	var rings := 18
	var radial := 26
	var grid := []
	for ri in rings + 1:
		var row := []
		var theta := PI * ri / rings
		for si in radial + 1:
			var phi := TAU * si / radial
			var unit := Vector3(sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi))
			row.append(IslandField.surface(island, unit, _noise))
		grid.append(row)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ri in rings:
		for si in radial:
			var a: Vector3 = grid[ri][si]
			var b: Vector3 = grid[ri][si + 1]
			var c: Vector3 = grid[ri + 1][si + 1]
			var d: Vector3 = grid[ri + 1][si]
			_tri(st, a, c, b)
			_tri(st, a, d, c)
	st.generate_normals()
	var mesh := st.commit()

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = island["pos"]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.25, 0.3)
	mat.roughness = 1.0
	mi.material_override = mat
	mi.visible = false
	reveal_meshes.append(mi)

	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(mesh.get_faces())
	shape.backface_collision = true
	var cs := CollisionShape3D.new()
	cs.shape = shape
	var body := StaticBody3D.new()
	body.position = island["pos"]
	body.add_child(cs)
	add_child(body)
	add_child(mi)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	if (b - a).cross(c - a).length_squared() < 0.0001:
		return
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


func _spawn_bird() -> void:
	var island: Dictionary = IslandField.ISLANDS[0]
	_spawn = island["pos"] + IslandField.surface(island, Vector3.UP, _noise) + Vector3(0, 2.5, 0)
	bird = CharacterBody3D.new()
	bird.set_script(BirdScript)
	add_child(bird)
	bird.reset(_spawn)
	# Proprioception is a real sense. You always know where your own wings are.
	bird.model.visible = true
	for child in bird.model.get_children():
		_dim_self(child)


func _dim_self(n: Node) -> void:
	if n is MeshInstance3D:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.30, 0.36, 0.45, 0.55)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		(n as MeshInstance3D).material_override = m
	for c in n.get_children():
		_dim_self(c)


func _build_air() -> void:
	air_mat = ShaderMaterial.new()
	air_mat.shader = load("res://air.gdshader")

	var centers := PackedVector3Array()
	var radii := PackedFloat32Array()
	for island in IslandField.ISLANDS:
		centers.append(island["pos"])
		radii.append(island["r"])
	air_mat.set_shader_parameter("islands", centers)
	air_mat.set_shader_parameter("island_r", radii)

	var th := PackedVector4Array()
	var tp := PackedVector4Array()
	for t in IslandField.THERMALS:
		var c: Vector3 = t["pos"]
		th.append(Vector4(c.x, c.y, c.z, t["radius"]))
		tp.append(Vector4(t["base"], t["top"], t["power"], 0.0))
	air_mat.set_shader_parameter("thermals", th)
	air_mat.set_shader_parameter("thermal_p", tp)

	# THE DYE. A box of volumetric fog that rides with the bird, whose density at
	# every point is decided by what the air is doing there. This is the medium.
	fog_mat = ShaderMaterial.new()
	fog_mat.shader = load("res://air_fog.gdshader")
	fog_mat.set_shader_parameter("islands", centers)
	fog_mat.set_shader_parameter("island_r", radii)
	fog_mat.set_shader_parameter("thermals", th)
	fog_mat.set_shader_parameter("thermal_p", tp)
	fog_volume = FogVolume.new()
	fog_volume.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	fog_volume.size = Vector3(260, 260, 260)
	fog_volume.material = fog_mat
	add_child(fog_volume)

	particles = GPUParticles3D.new()
	particles.process_material = air_mat
	particles.amount = QUALITY[quality]
	particles.lifetime = 6.0
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-120, -120, -120), Vector3(240, 240, 240))
	# The filament IS the trail. Each tracer drags a ribbon along the path it took
	# through the field, so what you see is not where the air is — it is where the
	# air has been going.
	particles.trail_enabled = true
	particles.trail_lifetime = 0.85   # long enough for an eddy to draw its own curl
	particles.draw_pass_1 = _filament_mesh()
	add_child(particles)


func _filament_mesh() -> Mesh:
	# A tube rather than a ribbon: it needs no billboarding, so a filament seen
	# end-on does not vanish. That matters when you are flying INTO the flow.
	# Hair-thin on purpose — a thick one is a shard, and a shard is not a contour.
	var tube := TubeTrailMesh.new()
	tube.radius = 0.055
	tube.radial_steps = 3
	tube.sections = 8
	tube.section_length = 0.4
	tube.section_rings = 1
	var mat := ShaderMaterial.new()
	mat.shader = load("res://air_draw.gdshader")
	tube.material = mat
	return tube


func _update_air() -> void:
	var p := bird.global_position
	var w := prevailing()
	fog_volume.global_position = p
	fog_mat.set_shader_parameter("prevailing", w)

	# The filaments survive, but only as a whisper on top of the smoke: a few
	# streaklines to say which way the fluid is running. The dye does the rest.
	particles.global_position = p
	air_mat.set_shader_parameter("prevailing", w)
	air_mat.set_shader_parameter("observer", p)
	# The frame the air is perceived in. See air.gdshader: the bird's own velocity
	# is subtracted out, so the medium shows its structure and not your speed.
	air_mat.set_shader_parameter("carrier", bird.velocity)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(16, 12)
	hud.add_theme_font_size_override("font_size", 14)
	hud.add_theme_color_override("font_color", Color(0.55, 0.62, 0.72))
	layer.add_child(hud)


func _update_hud() -> void:
	# The vario is a TEST INSTRUMENT, not a HUD. It exists so we can check
	# whether the percept told the truth. It does not ship.
	var vario := "  %+.1f m/s" % _climb
	if _climb > 1.5:
		vario += "   ^ LIFT"
	hud.text = "AIR — the wind sense, alone.   %d fps\n%s   %.0f m/s   alt %.0f m%s\nwind %.1f m/s\n\nfind a thermal you cannot see, and ride it\nmouse aim   WASD walk   SPACE flap/fly   SHIFT brake\nQ tracers: %s   F1 reveal the rock [%s]   R respawn   ESC mouse" % [
		Engine.get_frames_per_second(),
		bird.state_name(), bird.velocity.length(), bird.global_position.y, vario,
		wind_strength,
		QUALITY_NAMES[quality],
		"on" if revealed else "off",
	]

extends Node3D

# Aerie — bird flight prototype.
# Builds a small archipelago of floating islands, a bird you can walk and fly,
# and a mutable atmosphere: time of day, four seasons, and wind, all live.

const BirdScript := preload("res://bird.gd")

const SEASON_NAMES := ["SPRING", "SUMMER", "AUTUMN", "WINTER"]

const ISLANDS := [
	{ "pos": Vector3(0, 0, 0), "r": 42.0, "trees": 14, "updraft": false },
	{ "pos": Vector3(150, 18, 70), "r": 28.0, "trees": 9, "updraft": true },
	{ "pos": Vector3(-130, 30, 150), "r": 24.0, "trees": 7, "updraft": true },
	{ "pos": Vector3(55, -12, 235), "r": 34.0, "trees": 11, "updraft": false },
	{ "pos": Vector3(-70, 45, -170), "r": 20.0, "trees": 5, "updraft": true },
]

var time_of_day := 9.5
var auto_time := true
var time_scale := 0.15 # game-hours per real second
var season := 1.0
var season_target := 1.0
var wind_yaw := 0.8
var wind_strength := 1.0
var quality := 0 # 0 LOW, 1 MEDIUM, 2 HIGH — cycled with Q

const QUALITY_NAMES := ["LOW", "MEDIUM", "HIGH"]

var sun: DirectionalLight3D
var moon: DirectionalLight3D
var env: Environment
var bird: CharacterBody3D
var hud: Label
var ambient_particles: GPUParticles3D
var ambient_mat: ParticleProcessMaterial

var _t := 0.0
var _spawn_pos := Vector3.ZERO
var _noise := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()
var _island_mat: ShaderMaterial
var _leaf_mat: ShaderMaterial
var _trunk_mat := StandardMaterial3D.new()


func _enter_tree() -> void:
	_setup_actions()


func _ready() -> void:
	_noise.seed = 1337
	_noise.frequency = 1.0
	_rng.seed = 42
	_setup_materials()
	_build_environment()
	for i in ISLANDS.size():
		_build_island(ISLANDS[i])
	_build_cloud_floor()
	_build_ambient_particles()
	_apply_quality()
	_spawn_bird()
	_build_hud()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	_t += delta
	if Input.is_action_pressed("time_fwd"):
		time_of_day += delta * 3.0
	elif Input.is_action_pressed("time_back"):
		time_of_day -= delta * 3.0
	elif auto_time:
		time_of_day += delta * time_scale
	time_of_day = fposmod(time_of_day, 24.0)
	if Input.is_action_just_pressed("time_auto"):
		auto_time = not auto_time
	for i in 4:
		if Input.is_action_just_pressed("season_%d" % (i + 1)):
			season_target = float(i)
	if Input.is_action_just_pressed("quality"):
		quality = (quality + 1) % 3
		_apply_quality()
	season = lerpf(season, season_target, minf(1.0, delta * 0.6))
	wind_strength = 0.75 + 0.45 * sin(_t * 0.17) + 0.25 * sin(_t * 0.61)
	wind_yaw += delta * 0.015
	if Input.is_action_just_pressed("respawn") or bird.global_position.y < -160.0:
		_respawn()
	_update_environment()
	_update_globals()
	_update_ambient()
	_update_hud()


func wind_vector() -> Vector3:
	return Vector3(cos(wind_yaw), 0.0, sin(wind_yaw)) * wind_strength


# -- input ------------------------------------------------------------------

func _setup_actions() -> void:
	var defs := {
		"move_forward": KEY_W, "move_back": KEY_S,
		"move_left": KEY_A, "move_right": KEY_D,
		"flap": KEY_SPACE, "brake": KEY_SHIFT,
		"time_fwd": KEY_T, "time_back": KEY_G, "time_auto": KEY_Y,
		"season_1": KEY_1, "season_2": KEY_2, "season_3": KEY_3, "season_4": KEY_4,
		"respawn": KEY_R, "quality": KEY_Q,
	}
	for a in defs:
		if InputMap.has_action(a):
			continue
		InputMap.add_action(a)
		var ev := InputEventKey.new()
		ev.physical_keycode = defs[a]
		InputMap.action_add_event(a, ev)


# -- materials ---------------------------------------------------------------

func _setup_materials() -> void:
	_island_mat = ShaderMaterial.new()
	_island_mat.shader = load("res://island.gdshader")
	_leaf_mat = ShaderMaterial.new()
	_leaf_mat.shader = load("res://leaves.gdshader")
	_trunk_mat.albedo_color = Color(0.35, 0.25, 0.18)
	_trunk_mat.roughness = 1.0


# -- environment -------------------------------------------------------------

func _build_environment() -> void:
	env = Environment.new()
	var sky_mat := PhysicalSkyMaterial.new()
	sky_mat.sun_disk_scale = 5.0
	sky_mat.ground_color = Color(0.65, 0.7, 0.8)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.004
	env.volumetric_fog_albedo = Color(0.9, 0.95, 1.0)
	env.volumetric_fog_length = 220.0
	env.volumetric_fog_sky_affect = 0.2
	env.fog_enabled = true
	env.fog_density = 0.0004
	env.fog_aerial_perspective = 0.6
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.light_angular_distance = 1.2
	add_child(sun)

	# Moonlight fill so nights read; no shadows — a second shadowed
	# directional light doubles the shadow pass cost.
	moon = DirectionalLight3D.new()
	moon.rotation = Vector3(-0.9, 2.4, 0.0)
	moon.light_color = Color(0.55, 0.68, 1.0)
	moon.light_energy = 0.0
	moon.shadow_enabled = false
	add_child(moon)


func _apply_quality() -> void:
	var vp := get_viewport()
	match quality:
		0:
			env.volumetric_fog_enabled = false
			env.glow_enabled = false
			vp.scaling_3d_scale = 0.6
			vp.msaa_3d = Viewport.MSAA_DISABLED
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			sun.directional_shadow_max_distance = 100.0
			RenderingServer.directional_shadow_atlas_set_size(1024, true)
			ambient_particles.amount = 250
		1:
			env.volumetric_fog_enabled = true
			env.glow_enabled = true
			vp.scaling_3d_scale = 0.85
			vp.msaa_3d = Viewport.MSAA_DISABLED
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			sun.directional_shadow_max_distance = 200.0
			RenderingServer.directional_shadow_atlas_set_size(2048, true)
			ambient_particles.amount = 500
		2:
			env.volumetric_fog_enabled = true
			env.glow_enabled = true
			vp.scaling_3d_scale = 1.0
			vp.msaa_3d = Viewport.MSAA_2X
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			sun.directional_shadow_max_distance = 300.0
			RenderingServer.directional_shadow_atlas_set_size(4096, false)
			ambient_particles.amount = 900


func _update_environment() -> void:
	var t := time_of_day / 24.0
	var ang := (t - 0.25) * TAU # 6:00 sunrise, 12:00 zenith, 18:00 sunset
	sun.rotation = Vector3(-ang, 0.35, 0.0)
	var elev := sin(ang)
	sun.light_energy = clampf(elev * 1.7, 0.0, 1.4)
	sun.visible = elev > -0.03
	var warm := clampf(elev * 2.5, 0.0, 1.0)
	sun.light_color = Color(1.0, 0.55 + 0.45 * warm, 0.4 + 0.6 * warm)
	moon.light_energy = clampf(-elev * 2.0, 0.0, 1.0) * 0.22
	var w := _winterness()
	var night := clampf(-elev, 0.0, 1.0)
	if env.volumetric_fog_enabled:
		env.volumetric_fog_density = 0.003 + w * 0.004 + night * 0.0015
		env.fog_density = 0.0004
	else:
		env.fog_density = 0.0012 + w * 0.0015 + night * 0.0006


func _winterness() -> float:
	var s := fposmod(season, 4.0)
	var d: float = min(abs(s - 3.0), s + 1.0)
	return clampf(1.0 - d, 0.0, 1.0)


func _autumnness() -> float:
	return clampf(1.0 - abs(fposmod(season, 4.0) - 2.0), 0.0, 1.0)


func _update_globals() -> void:
	RenderingServer.global_shader_parameter_set("season", fposmod(season, 4.0))
	RenderingServer.global_shader_parameter_set("wind_strength", wind_strength)
	RenderingServer.global_shader_parameter_set(
		"wind_dir", Vector3(cos(wind_yaw), 0.0, sin(wind_yaw)))


# -- world building ----------------------------------------------------------

# Surface point of an island (local space) for a direction on the unit sphere.
# Top hemisphere flattens into a grassy dome, bottom stretches into a rocky root.
func _island_surface(island: Dictionary, unit: Vector3) -> Vector3:
	var r: float = island["r"]
	var seed_off: Vector3 = island["pos"] * 0.05
	var n := _noise.get_noise_3dv(unit * 2.5 + seed_off)
	var rr := r * (1.0 + 0.28 * n)
	var p := unit * rr
	if p.y >= 0.0:
		p.y *= 0.32
		var bump := _noise.get_noise_3dv(unit * 5.0 + seed_off + Vector3(9, 9, 9))
		p.y += bump * r * 0.09 * clampf(unit.y * 3.0, 0.0, 1.0)
	else:
		var pinch := 1.0 - 0.72 * (-unit.y)
		p.x *= pinch
		p.z *= pinch
		p.y *= 1.35
	return p


func _build_island(island: Dictionary) -> void:
	var rings := 20
	var radial := 30
	var grid := []
	for ri in rings + 1:
		var row := []
		var theta := PI * ri / rings
		for si in radial + 1:
			var phi := TAU * si / radial
			var unit := Vector3(sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi))
			var grass := clampf(unit.y * 2.2, 0.0, 1.0)
			grass *= 0.7 + 0.6 * _noise.get_noise_3dv(unit * 4.0 + island["pos"] * 0.03)
			row.append({ "p": _island_surface(island, unit), "g": clampf(grass, 0.0, 1.0) })
		grid.append(row)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for ri in rings:
		for si in radial:
			var a: Dictionary = grid[ri][si]
			var b: Dictionary = grid[ri][si + 1]
			var c: Dictionary = grid[ri + 1][si + 1]
			var d: Dictionary = grid[ri + 1][si]
			_add_tri(st, [a, c, b])
			_add_tri(st, [a, d, c])
	st.generate_normals()
	var mesh := st.commit()

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _island_mat
	mi.position = island["pos"]
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	(cs.shape as ConcavePolygonShape3D).backface_collision = true
	body.add_child(cs)
	mi.add_child(body)
	add_child(mi)

	for i in int(island["trees"]):
		var y := _rng.randf_range(0.55, 0.92)
		var phi := _rng.randf() * TAU
		var s := sqrt(1.0 - y * y)
		var unit := Vector3(s * cos(phi), y, s * sin(phi))
		var tree := _make_tree()
		tree.position = _island_surface(island, unit) + Vector3(0, -0.25, 0)
		tree.rotation.y = _rng.randf() * TAU
		mi.add_child(tree)

	if island["updraft"]:
		_add_updraft(island)


func _add_tri(st: SurfaceTool, verts: Array) -> void:
	var a: Vector3 = verts[0]["p"]
	var b: Vector3 = verts[1]["p"]
	var c: Vector3 = verts[2]["p"]
	if (b - a).cross(c - a).length_squared() < 0.0001:
		return
	for v in verts:
		st.set_color(Color(0.0, v["g"], 0.0))
		st.add_vertex(v["p"])


func _make_tree() -> Node3D:
	var tree := Node3D.new()
	var h := _rng.randf_range(2.5, 4.5)
	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.12
	tm.bottom_radius = 0.22
	tm.height = h
	tm.radial_segments = 6
	trunk.mesh = tm
	trunk.material_override = _trunk_mat
	trunk.position.y = h * 0.5
	tree.add_child(trunk)
	for i in 3:
		var leaf := MeshInstance3D.new()
		var lm := SphereMesh.new()
		lm.radial_segments = 7
		lm.rings = 4
		var s := _rng.randf_range(0.9, 1.6) * (1.0 - i * 0.15)
		lm.radius = s
		lm.height = s * 1.7
		leaf.mesh = lm
		leaf.material_override = _leaf_mat
		leaf.position = Vector3(
			_rng.randf_range(-0.5, 0.5), h * (0.72 + i * 0.22), _rng.randf_range(-0.5, 0.5))
		tree.add_child(leaf)
	return tree


func _add_updraft(island: Dictionary) -> void:
	var offset := Vector3(island["r"] + 10.0, 0, 0).rotated(Vector3.UP, _rng.randf() * TAU)
	var base_pos: Vector3 = island["pos"] + offset + Vector3(0, -25, 0)
	var node := Node3D.new()
	node.position = base_pos
	node.add_to_group("updraft")
	node.set_meta("radius", 8.0)
	node.set_meta("base", base_pos.y)
	node.set_meta("top", base_pos.y + 90.0)
	add_child(node)

	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 4.0
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 12.0
	pm.initial_velocity_max = 18.0
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3(0, 1, 0)
	pm.emission_ring_radius = 6.5
	pm.emission_ring_inner_radius = 1.5
	pm.emission_ring_height = 4.0
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	pm.color = Color(1.0, 1.0, 1.0, 0.25)
	var particles := GPUParticles3D.new()
	particles.process_material = pm
	particles.amount = 70
	particles.lifetime = 6.0
	particles.visibility_aabb = AABB(Vector3(-12, -5, -12), Vector3(24, 110, 24))
	var qm := QuadMesh.new()
	qm.size = Vector2(0.22, 1.6)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.vertex_color_use_as_albedo = true
	qm.material = dm
	particles.draw_pass_1 = qm
	node.add_child(particles)


func _build_cloud_floor() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6000, 6000)
	mi.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.82, 0.86, 0.92)
	mi.material_override = mat
	mi.position = Vector3(0, -115, 0)
	add_child(mi)


func _build_ambient_particles() -> void:
	ambient_mat = ParticleProcessMaterial.new()
	ambient_mat.direction = Vector3(0, -1, 0)
	ambient_mat.spread = 12.0
	ambient_mat.gravity = Vector3(0, -1.5, 0)
	ambient_mat.initial_velocity_min = 1.0
	ambient_mat.initial_velocity_max = 2.5
	ambient_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	ambient_mat.emission_box_extents = Vector3(35, 12, 35)
	ambient_particles = GPUParticles3D.new()
	ambient_particles.process_material = ambient_mat
	ambient_particles.amount = 900
	ambient_particles.lifetime = 7.0
	ambient_particles.visibility_aabb = AABB(Vector3(-60, -60, -60), Vector3(120, 120, 120))
	var qm := QuadMesh.new()
	qm.size = Vector2(0.14, 0.14)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.vertex_color_use_as_albedo = true
	qm.material = dm
	ambient_particles.draw_pass_1 = qm
	ambient_particles.emitting = false
	add_child(ambient_particles)


func _update_ambient() -> void:
	ambient_particles.global_position = bird.global_position + Vector3(0, 10, 0)
	var w := _winterness()
	var au := _autumnness()
	var wind := wind_vector()
	if w > 0.4:
		ambient_particles.emitting = true
		ambient_mat.color = Color(1.0, 1.0, 1.0, 0.9)
		ambient_mat.gravity = Vector3(wind.x * 1.5, -1.8, wind.z * 1.5)
		ambient_mat.scale_min = 0.5
		ambient_mat.scale_max = 1.0
	elif au > 0.5:
		ambient_particles.emitting = true
		ambient_mat.color = Color(0.8, 0.42, 0.1, 0.9)
		ambient_mat.gravity = Vector3(wind.x * 2.5, -1.2, wind.z * 2.5)
		ambient_mat.scale_min = 1.2
		ambient_mat.scale_max = 2.2
	else:
		ambient_particles.emitting = false


# -- bird & hud ---------------------------------------------------------------

func _spawn_bird() -> void:
	var island: Dictionary = ISLANDS[0]
	_spawn_pos = island["pos"] + _island_surface(island, Vector3.UP) + Vector3(0, 2.5, 0)
	bird = CharacterBody3D.new()
	bird.set_script(BirdScript)
	add_child(bird)
	bird.reset(_spawn_pos)


func _respawn() -> void:
	bird.reset(_spawn_pos)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(14, 10)
	hud.add_theme_font_size_override("font_size", 15)
	hud.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65))
	hud.add_theme_constant_override("shadow_offset_x", 1)
	hud.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(hud)


func _update_hud() -> void:
	var si := int(round(fposmod(season, 4.0))) % 4
	hud.text = "AERIE  —  %02d:%02d  %s  wind %.1f  |  %d fps\n%s  %.0f m/s\n\nmouse aim — the bird flies where you look\nWASD walk   SPACE jump / flap (in air: fly)   SHIFT air brake\nT/G scrub time   Y auto-time %s   1-4 season   R respawn\nQ quality: %s   ESC mouse" % [
		int(time_of_day), int(fmod(time_of_day, 1.0) * 60.0),
		SEASON_NAMES[si], wind_strength, int(Engine.get_frames_per_second()),
		bird.state_name(), bird.velocity.length(),
		"ON" if auto_time else "OFF",
		QUALITY_NAMES[quality],
	]

extends Node3D

# OPTION C — the spirit SEES, and the wind is what deforms what it sees.
#
# The island is visible: bold shapes, a small curated palette, quantised light.
# But it is still a percept, not a photograph. The air is not drawn — it is read
# off the world it bends. Schlieren: density gradients refract light, which is
# genuinely how invisible air is photographed, so no lines, no arrows, no motes.
#
#   calm air        -> almost nothing
#   a gust front    -> a ripple crossing the world ahead of the shove
#   a wake          -> a shimmering pocket downwind of rock
#   an updraft      -> the world STRETCHES upward through the lift
#
# The dye (air_fog) survives, demoted: it is now weather, not the whole world.
# The flight model and the field are unchanged — see island_field.gd, and the
# measured soaring test in air.tscn, which still passes.

const BirdScript := preload("res://bird.gd")

var bird: CharacterBody3D
var env: Environment
var sun: DirectionalLight3D
var fog_mat: ShaderMaterial
var fog_volume: FogVolume
var schlieren: ShaderMaterial
var hud: Label

var wind_yaw := 0.7
var wind_strength := 6.0
var _t := 0.0
var _spawn := Vector3.ZERO
var _noise := FastNoiseLite.new()
var _climb := 0.0
var _haze := 1.0


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
	_build_schlieren()
	_build_hud()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	_t += delta
	wind_strength = 5.5 + 2.2 * sin(_t * 0.13) + 1.1 * sin(_t * 0.47)
	wind_yaw += delta * 0.02
	if Input.is_action_just_pressed("respawn") or bird.global_position.y < -200.0:
		bird.reset(_spawn)
	if Input.is_action_just_pressed("quality"):
		_haze = 0.0 if _haze > 0.5 else 1.0
		fog_mat.set_shader_parameter("haze", 0.007 * _haze)

	_climb = lerpf(_climb, bird.velocity.y, minf(1.0, delta * 3.0))
	var p := bird.global_position
	var w := prevailing()
	fog_volume.global_position = p
	fog_mat.set_shader_parameter("prevailing", w)
	schlieren.set_shader_parameter("prevailing", w)
	_update_hud()


func prevailing() -> Vector3:
	return Vector3(cos(wind_yaw), 0.0, sin(wind_yaw)) * wind_strength


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
	# A small, curated palette — the sky is three colours and no more.
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.16, 0.28, 0.48)
	sky_mat.sky_horizon_color = Color(0.76, 0.80, 0.84)
	sky_mat.ground_bottom_color = Color(0.10, 0.14, 0.22)
	sky_mat.ground_horizon_color = Color(0.60, 0.66, 0.72)
	sky_mat.sun_angle_max = 12.0
	sky_mat.sun_curve = 0.08
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 2.0
	env.glow_enabled = true
	env.glow_intensity = 0.25
	env.glow_bloom = 0.05
	# Aerial perspective: distance reads as value, which is most of "atmospheric".
	# Restraint — stacked with the volumetric haze this drowns the world in milk.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.66, 0.73, 0.82)
	env.fog_density = 0.0007
	env.fog_aerial_perspective = 0.35
	env.fog_sky_affect = 0.0
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0
	env.volumetric_fog_length = 200.0
	env.volumetric_fog_detail_spread = 1.2
	env.volumetric_fog_ambient_inject = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation = Vector3(-0.62, 2.1, 0.0)
	sun.light_energy = 1.45
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 320.0
	add_child(sun)


func _build_island(island: Dictionary) -> void:
	var rings := 22
	var radial := 32
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
	st.set_smooth_group(-1)   # flat facets: bold shapes need hard edges
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

	var mat := ShaderMaterial.new()
	mat.shader = load("res://island_lit.gdshader")
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = island["pos"]
	add_child(mi)

	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(mesh.get_faces())
	shape.backface_collision = true
	var cs := CollisionShape3D.new()
	cs.shape = shape
	var body := StaticBody3D.new()
	body.position = island["pos"]
	body.add_child(cs)
	add_child(body)


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
	# The spring arm was jamming the camera into the bird's back whenever it stood
	# on a dome. Let it pass through rock for now; a flying camera clipping terrain
	# is a smaller lie than a camera buried in a wing.
	bird.arm.collision_mask = 0


func _build_air() -> void:
	var centers := PackedVector3Array()
	var radii := PackedFloat32Array()
	for island in IslandField.ISLANDS:
		centers.append(island["pos"])
		radii.append(island["r"])
	var th := PackedVector4Array()
	var tp := PackedVector4Array()
	for t in IslandField.THERMALS:
		var c: Vector3 = t["pos"]
		th.append(Vector4(c.x, c.y, c.z, t["radius"]))
		tp.append(Vector4(t["base"], t["top"], t["power"], 0.0))

	# The dye, demoted. It no longer IS the world — it is the weather in it.
	fog_mat = ShaderMaterial.new()
	fog_mat.shader = load("res://air_fog.gdshader")
	fog_mat.set_shader_parameter("islands", centers)
	fog_mat.set_shader_parameter("island_r", radii)
	fog_mat.set_shader_parameter("thermals", th)
	fog_mat.set_shader_parameter("thermal_p", tp)
	fog_mat.set_shader_parameter("haze", 0.0022)
	fog_volume = FogVolume.new()
	fog_volume.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	fog_volume.size = Vector3(380, 380, 380)
	fog_volume.material = fog_mat
	add_child(fog_volume)

	schlieren = ShaderMaterial.new()
	schlieren.shader = load("res://schlieren.gdshader")
	schlieren.set_shader_parameter("islands", centers)
	schlieren.set_shader_parameter("island_r", radii)
	schlieren.set_shader_parameter("thermals", th)
	schlieren.set_shader_parameter("thermal_p", tp)


func _build_schlieren() -> void:
	# A fullscreen pass riding the camera, drawn after the world so it has a world
	# to bend. Without something behind it, refraction refracts nothing — which is
	# exactly why this could not have been the first slice.
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = schlieren
	mi.extra_cull_margin = 1e5
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.sorting_offset = 2000.0
	bird.cam.add_child(mi)
	mi.position = Vector3(0, 0, -0.5)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(16, 12)
	hud.add_theme_font_size_override("font_size", 14)
	hud.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	hud.add_theme_constant_override("shadow_offset_x", 1)
	hud.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(hud)


func _update_hud() -> void:
	var vario := "  %+.1f m/s" % _climb
	if _climb > 1.5:
		vario += "   ^ LIFT"
	hud.text = "THE SPIRIT SEES — wind as schlieren.   %d fps\n%s   %.0f m/s   alt %.0f m%s\nwind %.1f m/s\n\nthe air is never drawn. read it in what it bends.\nmouse aim   WASD walk   SPACE flap/fly   SHIFT brake\nQ haze [%s]   R respawn   ESC mouse" % [
		Engine.get_frames_per_second(),
		bird.state_name(), bird.velocity.length(), bird.global_position.y, vario,
		wind_strength,
		"on" if _haze > 0.5 else "off",
	]


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.physical_keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

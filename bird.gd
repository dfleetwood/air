extends CharacterBody3D

# Bird controller: walking plus arcade glide flight.
# In flight the bird steers toward wherever the camera aims. Diving trades
# altitude for speed, climbing bleeds it off; SPACE flaps, SHIFT air-brakes.
# Updrafts (group "updraft") and the world wind push the bird around.

enum { STATE_WALK, STATE_FLY }

const WALK_SPEED := 6.0
const WALK_ACCEL := 28.0
const JUMP_VELOCITY := 8.5
const GRAVITY := 24.0
const MIN_FLY_SPEED := 4.0
const MAX_FLY_SPEED := 45.0
const TRIM_SPEED := 11.0
const MOUSE_SENS := 0.0024

var state := STATE_WALK
var cam_yaw := 0.0
var cam_pitch := -0.2
var fly_yaw := 0.0
var fly_pitch := 0.0
var fly_speed := 0.0
var bank := 0.0
var flap_anim := 0.0

var rig: Node3D
var arm: SpringArm3D
var cam: Camera3D
var model: Node3D
var wing_l: Node3D
var wing_r: Node3D

var _t := 0.0


func _ready() -> void:
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.35
	cs.shape = sph
	add_child(cs)
	_build_model()
	_build_camera()


func reset(p: Vector3) -> void:
	global_position = p
	velocity = Vector3.ZERO
	state = STATE_WALK
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	fly_speed = 0.0
	if rig:
		rig.global_position = p


# Put the bird straight into the air, pointed somewhere. Used by the autopilot
# test in air.gd, and by anything that wants to skip the launch.
func start_flight(yaw: float, pitch: float, speed: float) -> void:
	cam_yaw = yaw
	cam_pitch = pitch
	fly_yaw = yaw
	fly_pitch = pitch
	fly_speed = speed
	state = STATE_FLY
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING


func state_name() -> String:
	if state == STATE_FLY:
		return "FLYING"
	return "WALKING" if is_on_floor() else "AIRBORNE"


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		cam_yaw = wrapf(cam_yaw - event.relative.x * MOUSE_SENS, -PI, PI)
		cam_pitch = clampf(cam_pitch - event.relative.y * MOUSE_SENS, -1.35, 1.3)
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	match state:
		STATE_WALK:
			_walk(delta)
		STATE_FLY:
			_fly(delta)
	if state == STATE_FLY:
		model.rotation = Vector3(fly_pitch, fly_yaw, bank)


func _process(delta: float) -> void:
	_t += delta
	flap_anim = maxf(0.0, flap_anim - delta)
	_update_wings()
	_update_camera(delta)


# -- states -------------------------------------------------------------------

func _walk(dt: float) -> void:
	velocity.y -= GRAVITY * dt
	var iv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var f := Vector3(-sin(cam_yaw), 0.0, -cos(cam_yaw))
	var r := Vector3(cos(cam_yaw), 0.0, -sin(cam_yaw))
	var wish := f * -iv.y + r * iv.x
	if wish.length_squared() > 1.0:
		wish = wish.normalized()
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	flat = flat.move_toward(wish * WALK_SPEED, WALK_ACCEL * dt)
	velocity.x = flat.x
	velocity.z = flat.z
	if Input.is_action_just_pressed("flap"):
		if is_on_floor():
			velocity.y = JUMP_VELOCITY
		else:
			_start_fly()
			return
	move_and_slide()
	if wish.length_squared() > 0.01:
		var target_yaw := atan2(-wish.x, -wish.z)
		model.rotation.y = lerp_angle(model.rotation.y, target_yaw, minf(1.0, 10.0 * dt))
	model.rotation.x = lerpf(model.rotation.x, 0.0, minf(1.0, 8.0 * dt))
	model.rotation.z = lerpf(model.rotation.z, 0.0, minf(1.0, 8.0 * dt))


func _start_fly() -> void:
	state = STATE_FLY
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	fly_yaw = cam_yaw
	fly_pitch = clampf(cam_pitch, -0.4, 0.5)
	fly_speed = maxf(Vector2(velocity.x, velocity.z).length() + 4.0, 10.0)
	flap_anim = 0.5


func _fly(dt: float) -> void:
	var prev_yaw := fly_yaw
	fly_yaw = lerp_angle(fly_yaw, cam_yaw, minf(1.0, 2.4 * dt))
	fly_pitch = lerpf(fly_pitch, clampf(cam_pitch, -1.25, 1.1), minf(1.0, 2.8 * dt))
	var yaw_rate := angle_difference(prev_yaw, fly_yaw) / maxf(dt, 0.0001)
	bank = lerpf(bank, clampf(yaw_rate * 0.55, -1.1, 1.1), minf(1.0, 6.0 * dt))

	var fwd := Basis.from_euler(Vector3(fly_pitch, fly_yaw, 0.0)) * Vector3.FORWARD
	fly_speed += -fwd.y * 17.0 * dt              # dive to gain speed, climb to bleed it
	fly_speed -= (fly_speed - TRIM_SPEED) * 0.3 * dt
	if Input.is_action_just_pressed("flap"):
		fly_speed += 4.0
		flap_anim = 0.5
	if Input.is_action_pressed("brake"):
		fly_speed -= 20.0 * dt
	fly_speed = clampf(fly_speed, MIN_FLY_SPEED, MAX_FLY_SPEED)

	velocity = fwd * fly_speed
	var stall := clampf((8.0 - fly_speed) / 5.0, 0.0, 1.0)
	velocity += Vector3.DOWN * stall * 6.0
	var m := get_parent()
	if m and m.has_method("wind_at"):
		# The air the bird flies through is the same air the player perceives.
		velocity += m.wind_at(global_position)
	else:
		velocity.y += _updraft_lift()
		if m and m.has_method("wind_vector"):
			velocity += m.wind_vector() * 0.5

	move_and_slide()
	for i in get_slide_collision_count():
		var n := get_slide_collision(i).get_normal()
		if n.y > 0.45:
			_land()
			return
		fly_speed = maxf(fly_speed * 0.5, MIN_FLY_SPEED)


func _land() -> void:
	state = STATE_WALK
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	velocity = Vector3(velocity.x, 0.0, velocity.z) * 0.4
	model.rotation = Vector3(0.0, fly_yaw, 0.0)


func _updraft_lift() -> float:
	var lift := 0.0
	for u in get_tree().get_nodes_in_group("updraft"):
		var p: Vector3 = u.global_position
		var r: float = u.get_meta("radius")
		var dxz := Vector2(global_position.x - p.x, global_position.z - p.z).length()
		if dxz < r and global_position.y > u.get_meta("base") \
				and global_position.y < u.get_meta("top"):
			lift = maxf(lift, 3.0 + 8.0 * (1.0 - dxz / r))
	return lift


# -- visuals ------------------------------------------------------------------

func _update_wings() -> void:
	var fold := 1.0 if state == STATE_WALK else 0.0
	var flap := 0.0
	if state == STATE_FLY:
		if flap_anim > 0.0:
			flap = sin(_t * 24.0) * 0.85
		else:
			flap = sin(_t * 2.3) * 0.07
	wing_l.rotation.z = -fold * 1.2 + flap
	wing_r.rotation.z = fold * 1.2 - flap


func _update_camera(dt: float) -> void:
	rig.global_position = rig.global_position.lerp(
		global_position + Vector3.UP * 0.9, minf(1.0, 14.0 * dt))
	rig.rotation = Vector3(cam_pitch, cam_yaw, 0.0)
	var target_len := 5.0 if state == STATE_WALK else 4.5 + fly_speed * 0.09
	arm.spring_length = lerpf(arm.spring_length, target_len, minf(1.0, 4.0 * dt))
	var target_fov := 70.0 if state == STATE_WALK else 68.0 + fly_speed * 0.5
	cam.fov = lerpf(cam.fov, target_fov, minf(1.0, 3.0 * dt))


func _build_camera() -> void:
	rig = Node3D.new()
	rig.top_level = true
	add_child(rig)
	arm = SpringArm3D.new()
	arm.spring_length = 5.5
	arm.margin = 0.3
	arm.add_excluded_object(get_rid())
	rig.add_child(arm)
	cam = Camera3D.new()
	cam.far = 2000.0
	cam.current = true
	arm.add_child(cam)


func _build_model() -> void:
	model = Node3D.new()
	add_child(model)

	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.92, 0.92, 0.95)
	body_mat.roughness = 0.9
	var wing_mat := StandardMaterial3D.new()
	wing_mat.albedo_color = Color(0.42, 0.46, 0.55)
	wing_mat.roughness = 0.9
	var beak_mat := StandardMaterial3D.new()
	beak_mat.albedo_color = Color(0.95, 0.55, 0.15)
	beak_mat.roughness = 0.7

	var body := CapsuleMesh.new()
	body.radius = 0.28
	body.height = 1.05
	body.radial_segments = 10
	body.rings = 4
	_mesh_inst(body, body_mat, Vector3.ZERO, model, Vector3(PI / 2.0, 0, 0))

	var head := SphereMesh.new()
	head.radius = 0.2
	head.height = 0.4
	head.radial_segments = 10
	head.rings = 5
	_mesh_inst(head, body_mat, Vector3(0, 0.18, -0.5), model)

	var beak := CylinderMesh.new()
	beak.top_radius = 0.0
	beak.bottom_radius = 0.07
	beak.height = 0.3
	beak.radial_segments = 6
	_mesh_inst(beak, beak_mat, Vector3(0, 0.15, -0.75), model, Vector3(-PI / 2.0, 0, 0))

	var tail := BoxMesh.new()
	tail.size = Vector3(0.34, 0.06, 0.5)
	_mesh_inst(tail, wing_mat, Vector3(0, 0.05, 0.66), model)

	wing_l = Node3D.new()
	wing_l.position = Vector3(-0.22, 0.1, 0)
	model.add_child(wing_l)
	var wl := BoxMesh.new()
	wl.size = Vector3(1.4, 0.06, 0.6)
	_mesh_inst(wl, wing_mat, Vector3(-0.7, 0, 0.08), wing_l)

	wing_r = Node3D.new()
	wing_r.position = Vector3(0.22, 0.1, 0)
	model.add_child(wing_r)
	var wr := BoxMesh.new()
	wr.size = Vector3(1.4, 0.06, 0.6)
	_mesh_inst(wr, wing_mat, Vector3(0.7, 0, 0.08), wing_r)


func _mesh_inst(mesh: Mesh, mat: Material, pos: Vector3, parent: Node3D,
		rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi

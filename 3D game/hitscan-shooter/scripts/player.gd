extends CharacterBody3D

# amount: ติดลบ = โดนดาเมจ, บวก = ฮิล, 0 = ส่งค่าเริ่มต้น
signal health_changed(current: float, max_value: float, amount: float)
signal died

# --- Health ---
@export var max_health := 100.0
@export var debug_keys := true   # K = โดน 15, L = ฮิล 15 (ไว้ทดสอบ ปิดได้เมื่อมีมอนแล้ว)

# --- Movement ---
const WALK_SPEED := 7.0
const SPRINT_SPEED := 12.0
const CROUCH_SPEED := 3.5
const JUMP_VELOCITY := 5.0
const MOUSE_SENS := 0.003

const GROUND_ACCEL := 60.0
const AIR_ACCEL := 10.0

# --- Crouch / Slide ---
const CROUCH_HEIGHT := 1.3            # ความสูงแคปซูลตอนย่อ (ตอนยืนอ่านจาก CapsuleShape3D เอง)
const BODY_HEIGHT_SPEED := 6.0        # เมตร/วินาที ที่ตัวลด/สูงขึ้น (ยิ่งมากยิ่งไว)
const SLIDE_MIN_START_SPEED := 9.0    # ต้องเร็วกว่านี้ถึงจะสไลด์ได้ (เดิน 7 = ย่อเฉยๆ, วิ่ง 12 = สไลด์)
const SLIDE_BOOST := 1.15             # คูณความเร็วตอนเริ่มสไลด์
const SLIDE_MAX_SPEED := 14.0         # เพดานความเร็วตอนเริ่มสไลด์
const SLIDE_FRICTION := 7.0           # m/s² ที่ความเร็วลดลงระหว่างสไลด์ (มาก = สไลด์สั้น)
const SLIDE_END_SPEED := CROUCH_SPEED + 0.5   # ช้ากว่านี้ = จบสไลด์ กลายเป็นย่อปกติ
const SLIDE_COOLDOWN := 0.5           # กันสไลด์รัวเพื่อสะสมความเร็ว
const SLIDE_FOV := 90.0

# --- FOV ---
const BASE_FOV := 75.0
const SPRINT_FOV := 85.0
const FOV_SPEED := 8.0

# --- Camera sway (โยกตัวตามน้ำหนักเท้า) ---
@export_range(0.0, 2.0) var sway_intensity := 1.0   # 0 = ปิด

const STEP_RATE_BASE := 4.0
const STEP_RATE_PER_MS := 0.6
const LATERAL := 0.06
const VERTICAL := 0.035
const ROLL_DEG := 1.0
const YAW_DEG := 0.7
const PITCH_DEG := 0.4
const AMP_SMOOTH := 6.0

const IDLE_POS := 0.004
const STRAFE_TILT_DEG := 1.5
const STRAFE_SMOOTH := 6.0

# --- Recoil (สปริง) --- ชุดค่า Desert Eagle
const KICK_STIFFNESS := 220.0     # ยิ่งมาก ยิ่งดีดกลับไว
const KICK_DAMPING := 18.0        # ยิ่งน้อย ยิ่งเด้งเลย/สั่นค้าง (วิกฤต ≈ 27-30)
const KICK_IMPULSE_SCALE := 36.0  # แปลงค่า kick เป็นแรงกระแทก
const AIM_RECOIL_RETURN := 8.0    # องศา/วินาที ที่ปืนเด้งกลับลงเอง
const AIM_RECOIL_MAX := 15.0      # เพดานแรงดีดสะสม (องศา)

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var is_sprinting := false
var is_crouched := false   # สคริปต์อื่นอ่านได้ (เช่น weapon.gd ทำ spread)
var is_sliding := false    # สคริปต์อื่นอ่านได้
var health := 100.0
var is_dead := false
var speed_mult := 1.0      # การ์ดความสามารถปรับค่านี้ (คูณความเร็วเดิน/วิ่ง/ย่อ)

var _step_phase := 0.0
var _sway_amp := 0.0
var _strafe_tilt := 0.0

var _kick_pos := Vector3.ZERO   # (pitch, yaw, roll) องศา ภาพล้วน
var _kick_vel := Vector3.ZERO
var _aim_recoil := 0.0          # องศาที่ปลายกระบอกเด้งค้างอยู่

var _slide_cooldown := 0.0

# ข้อมูลตัวละครตอนยืน (อ่านจาก scene ตอน _ready)
var _capsule: CapsuleShape3D
var _test_shape: CapsuleShape3D   # ใช้ตรวจเพดานก่อนลุก
var _stand_height := 2.0
var _crouch_height := CROUCH_HEIGHT
var _stand_col_y := 0.0
var _stand_head_y := 0.0
var _cur_height := 2.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var _collision: CollisionShape3D = $CollisionShape3D

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	camera.fov = BASE_FOV

	# ทำสำเนา shape เพื่อปรับความสูงตอนรันไทม์ได้โดยไม่แตะไฟล์ scene
	_capsule = (_collision.shape as CapsuleShape3D).duplicate()
	_collision.shape = _capsule

	_stand_height = _capsule.height
	_cur_height = _stand_height
	_crouch_height = maxf(CROUCH_HEIGHT, _capsule.radius * 2.0 + 0.05)
	_stand_col_y = _collision.position.y
	_stand_head_y = head.position.y

	_test_shape = CapsuleShape3D.new()
	_test_shape.radius = _capsule.radius
	_test_shape.height = _stand_height - 0.1   # เล็กกว่านิดหน่อย กันชนพื้นเอง

	# เลือดเริ่มต้น (ต้องทำที่นี่ เพราะค่า @export จะถูกใส่หลังตอนประกาศตัวแปร)
	health = max_health
	health_changed.emit(health, max_health, 0.0)

func _unhandled_input(event: InputEvent) -> void:
	if debug_keys and OS.is_debug_build() and event is InputEventKey \
	and event.pressed and not event.echo:
		if event.keycode == KEY_K:
			take_damage(15.0)
		elif event.keycode == KEY_L:
			heal(15.0)

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not is_dead:
		rotate_y(-event.relative.x * MOUSE_SENS)
		head.rotate_x(-event.relative.y * MOUSE_SENS)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))

	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	var on_floor := is_on_floor()
	var h_speed := Vector2(velocity.x, velocity.z).length()
	_slide_cooldown = maxf(_slide_cooldown - delta, 0.0)

	# ตายแล้ว: ไม่รับปุ่ม แค่ตกลงพื้นและไถลหยุด
	if is_dead:
		if not on_floor:
			velocity.y -= gravity * delta
		velocity.x = move_toward(velocity.x, 0.0, GROUND_ACCEL * 0.3 * delta)
		velocity.z = move_toward(velocity.z, 0.0, GROUND_ACCEL * 0.3 * delta)
		move_and_slide()
		return

	# ท่าทาง: ยืน / ย่อ / สไลด์
	_update_stance(on_floor, h_speed)
	_update_body_height(delta)

	# แรงโน้มถ่วง + กระโดด
	var jumped := false
	if not on_floor:
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = JUMP_VELOCITY
		jumped = true
		if is_sliding:
			_end_slide(true)   # กระโดดออกจากสไลด์ พาโมเมนตัมไปด้วย

	# ทิศทางที่กด
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	# วิ่ง (อัปเดตเฉพาะตอนอยู่บนพื้น เพื่อคงสถานะกลางอากาศ) ย่ออยู่วิ่งไม่ได้
	if on_floor and not jumped:
		is_sprinting = Input.is_action_pressed("sprint") and input_dir.y < -0.1 and not is_crouched

	if is_sliding:
		# สไลด์: ควบคุมทิศไม่ได้ ความเร็วลดลงจากแรงเสียดทานอย่างเดียว
		var speed := move_toward(h_speed, 0.0, SLIDE_FRICTION * delta)
		var dir := Vector3(velocity.x, 0.0, velocity.z).normalized()
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
	else:
		var target_speed := WALK_SPEED
		if is_sprinting:
			target_speed = SPRINT_SPEED
		elif is_crouched and on_floor:
			target_speed = CROUCH_SPEED
		var target_velocity := direction * target_speed * speed_mult
		var accel := GROUND_ACCEL if (on_floor and not jumped) else AIR_ACCEL

		velocity.x = move_toward(velocity.x, target_velocity.x, accel * delta)
		velocity.z = move_toward(velocity.z, target_velocity.z, accel * delta)

	move_and_slide()

	# FOV
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var fast := is_sprinting and horizontal_speed > WALK_SPEED + 0.5
	var target_fov := BASE_FOV
	if is_sliding:
		target_fov = SLIDE_FOV
	elif fast:
		target_fov = SPRINT_FOV
	camera.fov = lerpf(camera.fov, target_fov, FOV_SPEED * delta)

	_update_recoil(delta)
	_update_camera_sway(delta, horizontal_speed)

# ---------------------------------------------------------------
# Health
# ---------------------------------------------------------------
# มอน/กับดัก/AOE เรียก player.take_damage(จำนวน) ได้เลย (ชื่อเดียวกับ target.gd)
func take_damage(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	health_changed.emit(health, max_health, -amount)
	if health <= 0.0:
		_die()

func heal(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	var before := health
	health = minf(health + amount, max_health)
	if health > before:
		health_changed.emit(health, max_health, health - before)

func _die() -> void:
	is_dead = true
	is_sliding = false
	is_sprinting = false
	camera.set_process(false)   # หยุด weapon.gd (ยิงไม่ได้อีก)
	died.emit()                 # ข้อ 3 (หน้าจอตาย) จะมาฟัง signal นี้

# ---------------------------------------------------------------
# Crouch / Slide
# ---------------------------------------------------------------
func _update_stance(on_floor: bool, h_speed: float) -> void:
	var crouch_held := Input.is_action_pressed("crouch")

	# เริ่มสไลด์: กดย่อตอนวิ่งเร็วพอ
	if not is_sliding and on_floor and _slide_cooldown <= 0.0 \
	and Input.is_action_just_pressed("crouch") and h_speed >= SLIDE_MIN_START_SPEED * speed_mult:
		_start_slide(h_speed)
	# จบสไลด์: ปล่อยปุ่ม / หลุดจากพื้น / ช้าลงพอแล้ว
	elif is_sliding and (not crouch_held or not on_floor or h_speed <= SLIDE_END_SPEED):
		_end_slide(not on_floor)

	# ย่อ: ค้างปุ่มไว้ หรือกำลังสไลด์ หรือมีเพดานขวางจนลุกไม่ได้
	var want_crouch := crouch_held or is_sliding
	if is_crouched and not want_crouch and not _can_stand():
		want_crouch = true
	is_crouched = want_crouch

func _start_slide(h_speed: float) -> void:
	is_sliding = true
	is_sprinting = false
	var dir := Vector3(velocity.x, 0.0, velocity.z).normalized()
	var boosted := maxf(h_speed, minf(h_speed * SLIDE_BOOST, SLIDE_MAX_SPEED * speed_mult))
	velocity.x = dir.x * boosted
	velocity.z = dir.z * boosted

func _end_slide(carry_momentum: bool) -> void:
	is_sliding = false
	_slide_cooldown = SLIDE_COOLDOWN
	# ถ้าออกจากสไลด์ทางอากาศ (กระโดด/ตกขอบ) ให้คงความเร็วแบบวิ่งไว้ ไม่ให้เบรกกลางอากาศ
	if carry_momentum and Vector2(velocity.x, velocity.z).length() > WALK_SPEED + 0.5:
		is_sprinting = true

func _can_stand() -> bool:
	# เช็คว่าแคปซูลขนาดตอนยืนไปชนอะไรไหม (ไม่ต้องเพิ่ม RayCast ใน scene)
	var feet_y := _collision.global_position.y - _capsule.height * 0.5
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _test_shape
	params.transform = Transform3D(
		Basis.IDENTITY,
		Vector3(_collision.global_position.x, feet_y + _stand_height * 0.5, _collision.global_position.z)
	)
	params.exclude = [get_rid()]
	params.collision_mask = collision_mask
	return get_world_3d().direct_space_state.intersect_shape(params, 1).is_empty()

func _update_body_height(delta: float) -> void:
	var target_h := _crouch_height if is_crouched else _stand_height
	_cur_height = move_toward(_cur_height, target_h, BODY_HEIGHT_SPEED * delta)

	# เท้าอยู่ที่เดิม ลดความสูงจากด้านบน แล้วกดหัว/กล้องลงตามส่วนที่หายไป
	var diff := _stand_height - _cur_height
	_capsule.height = _cur_height
	_collision.position.y = _stand_col_y - diff * 0.5
	head.position.y = _stand_head_y - diff

# ---------------------------------------------------------------
# Camera sway
# ---------------------------------------------------------------
func _update_camera_sway(delta: float, horizontal_speed: float) -> void:
	var grounded := is_on_floor()
	var t := Time.get_ticks_msec() / 1000.0

	var target_amp := 0.0
	if grounded and not is_sliding:
		target_amp = clampf(horizontal_speed / SPRINT_SPEED, 0.0, 1.0)
	_sway_amp = lerpf(_sway_amp, target_amp, clampf(AMP_SMOOTH * delta, 0.0, 1.0))

	if grounded and not is_sliding and horizontal_speed > 0.1:
		_step_phase += (STEP_RATE_BASE + horizontal_speed * STEP_RATE_PER_MS) * delta
		_step_phase = fmod(_step_phase, TAU)

	var s := sin(_step_phase)
	var c := cos(_step_phase)

	var lateral := s * LATERAL * _sway_amp
	var vertical := -cos(_step_phase * 2.0) * VERTICAL * _sway_amp

	var idle := 1.0 - _sway_amp
	var idle_x := sin(t * 0.9) * IDLE_POS * idle
	var idle_y := sin(t * 1.3) * IDLE_POS * idle

	var local_vel := global_transform.basis.inverse() * velocity
	var strafe_target := -local_vel.x / SPRINT_SPEED * STRAFE_TILT_DEG
	_strafe_tilt = lerpf(_strafe_tilt, strafe_target, clampf(STRAFE_SMOOTH * delta, 0.0, 1.0))

	var roll := deg_to_rad(-s * ROLL_DEG * _sway_amp + _strafe_tilt)
	var yaw := deg_to_rad(c * YAW_DEG * _sway_amp)
	var pitch := deg_to_rad(sin(_step_phase * 2.0) * PITCH_DEG * _sway_amp)

	# แรงสะบัดจาก recoil (ภาพล้วน)
	var kick_rot := Vector3(
		deg_to_rad(_kick_pos.x),
		deg_to_rad(_kick_pos.y),
		deg_to_rad(_kick_pos.z)
	)

	camera.position = Vector3(lateral + idle_x, vertical + idle_y, 0.0) * sway_intensity
	camera.rotation = Vector3(pitch, yaw, roll) * sway_intensity + kick_rot

# ---------------------------------------------------------------
# Recoil
# ---------------------------------------------------------------
# kick_*    = สะบัดภาพผ่านสปริง (คืนตัวเอง ไม่กระทบจุดเล็ง)
# aim_pitch = ปลายกระบอกเด้งขึ้นจริง (คืนช้าๆ ผู้เล่นต้องชดเชย)
# aim_yaw   = ปลายกระบอกส่ายจริง (ไม่คืนเอง)
func apply_recoil(kick_pitch: float, kick_yaw: float, kick_roll: float, aim_pitch: float, aim_yaw: float) -> void:
	_kick_vel += Vector3(kick_pitch, kick_yaw, kick_roll) * KICK_IMPULSE_SCALE

	var add := minf(aim_pitch, AIM_RECOIL_MAX - _aim_recoil)
	if add > 0.0:
		head.rotate_x(deg_to_rad(add))
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))
		_aim_recoil += add

	rotate_y(deg_to_rad(aim_yaw))

func _update_recoil(delta: float) -> void:
	# สปริง: แรงดึงเข้าหาศูนย์ - แรงหน่วง
	var accel := -KICK_STIFFNESS * _kick_pos - KICK_DAMPING * _kick_vel
	_kick_vel += accel * delta
	_kick_pos += _kick_vel * delta

	# ปลายกระบอกค่อยๆ เด้งกลับลง
	var back := minf(_aim_recoil, AIM_RECOIL_RETURN * delta)
	if back > 0.0:
		head.rotate_x(-deg_to_rad(back))
		_aim_recoil -= back

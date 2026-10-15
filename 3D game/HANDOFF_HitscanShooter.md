# HitscanShooter: เอกสารส่งต่องาน (Handoff)

> **สำหรับ Claude ตัวถัดไป:** เอกสารนี้สรุปทุกอย่างที่ทำไปแล้วในโปรเจคเกม 3D บน Godot ผู้ใช้สื่อสารเป็น **ภาษาไทย** ให้ตอบเป็นภาษาไทย ผู้ใช้ชอบให้ **ส่งสคริปต์ทั้งไฟล์** (ไม่ใช่แค่ส่วนที่แก้) ชอบขั้นตอนแบบ Step by Step และอยากให้ช่วยเสนอไอเดียแมคคานิคเพิ่มเติม ไม่ใช่ทำตามอย่างเดียว

---

## 1. ภาพรวมโปรเจค

- **ชื่อโปรเจค:** HitscanShooter (เป็นงานโปรเจค)
- **เอนจิน:** Godot **4.7.2** (stable), GDScript, Renderer **Forward+**
- **OS:** Linux (Godot ติดตั้งผ่าน Steam/snap ที่ `/home/dong/snap/steam/common/hitscan-shooter` ตอนสร้างโปรเจค)
- **แนวเกม:** FPS แอคชั่นเร็ว เน้นการเคลื่อนไหว (วิ่ง ย่อ สไลด์) และปืนที่ให้ความรู้สึกหนักแน่น
- **หมายเหตุ:** Godot 4.4+ เปิดเกมแบบฝังใน editor โดยเริ่มต้น (หน้าต่างเล็ก) แนะนำให้ปิด "Embed Game on Next Play" หรือใช้ Stretch to Fit

### แนวคิดหลักของระบบยิง (ไอเดียของผู้ใช้)

**Hitscan + Delayed Impact** ไม่มี Projectile object:

1. ตอนกดยิง ทำ raycast ทันทีจากกล้องไปข้างหน้าตามระยะสูงสุด (`max_range = 500 ม.`)
2. ถ้าเจอวัตถุ (หรือมีอะไรมาบังก่อน) = ถือว่าโดนวัตถุแรกที่ชน
3. วัตถุอยู่เกินระยะ (เช่น 501 ม.) = ไม่โดน
4. คำนวณเวลาเดินทางจำลอง `travel_time = distance / bullet_speed` แล้วหน่วงเวลาก่อนแสดงจุด impact และทำ damage
5. ยิ่งไกล ยิ่งหน่วงนาน ทั้งที่ไม่มี object กระสุนพุ่งออกไปจริง

**ข้อจำกัดที่ยอมรับแล้ว:** ตรวจการชนตอนยิง ไม่ใช่ตอนกระสุนถึง ดังนั้นเป้าที่วิ่งหนีในช่วงหน่วงก็ยังโดนอยู่ (ยังไม่ได้ตัดสินใจเปลี่ยน ดูหัวข้อ Roadmap)

---

## 2. โครงสร้างโปรเจค

```
res://
├── scenes/
│   ├── world.tscn     (Main Scene)
│   ├── player.tscn
│   ├── impact.tscn
│   └── target.tscn
└── scripts/
    ├── player.gd
    ├── weapon.gd
    ├── crosshair.gd
    ├── impact.gd
    └── target.gd
```

### Scene: player.tscn

```
Player (CharacterBody3D)          <- player.gd
├── CollisionShape3D              (CapsuleShape3D)
├── Head (Node3D)                 (Position Y = 0.7)
│   └── Camera3D                  <- weapon.gd  (Far = 1000)
└── CanvasLayer
    └── Crosshair (Control)       <- crosshair.gd (Layout: Full Rect, Mouse Filter: Ignore)
```

### Scene: world.tscn

- `CSGBox3D` เป็นพื้น ขนาด (1000, 1, 1000) Position Y = -0.5 ติ๊ก **Use Collision**
- `DirectionalLight3D`
- `player.tscn` ที่ (0, 1, 0)
- `target.tscn` หลายตัววางระยะ z = -50, -200, -500, -550 (เพื่อทดสอบระยะ 500 ม. และเกิน 500 ม.) เหลื่อม x เล็กน้อยไม่ให้บังกัน
- (ไม่บังคับ) `WorldEnvironment`

### Scene: impact.tscn

`Node3D` (impact.gd) > `MeshInstance3D` (SphereMesh รัศมี 0.15 สีแดง มี Emission)

### Scene: target.tscn

`StaticBody3D` (target.gd) > `MeshInstance3D` (BoxMesh 2x2x2) + `CollisionShape3D` (BoxShape3D 2x2x2)

### Input Map (Project Settings)

| Action | ปุ่ม |
|---|---|
| `move_forward` | W |
| `move_back` | S |
| `move_left` | A |
| `move_right` | D |
| `jump` | Space |
| `sprint` | Left Shift |
| `shoot` | Left Mouse Button |

(ยังไม่มี action สำหรับย่อ/สไลด์ ต้องเพิ่มเมื่อทำ เช่น `crouch` = C หรือ Ctrl)

---

## 3. สคริปต์ทั้งหมด (สถานะปัจจุบัน)

ค่าที่ตั้งไว้เป็นชุด **"ฟีล Desert Eagle"** ที่ผู้ใช้ชอบแล้ว (สะบัดแรง ยิงช้า นัดหนัก)

### scripts/player.gd

```gdscript
extends CharacterBody3D

# --- Movement ---
const WALK_SPEED := 7.0
const SPRINT_SPEED := 12.0
const JUMP_VELOCITY := 5.0
const MOUSE_SENS := 0.003

const GROUND_ACCEL := 60.0
const AIR_ACCEL := 10.0

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

var _step_phase := 0.0
var _sway_amp := 0.0
var _strafe_tilt := 0.0

var _kick_pos := Vector3.ZERO   # (pitch, yaw, roll) องศา ภาพล้วน
var _kick_vel := Vector3.ZERO
var _aim_recoil := 0.0          # องศาที่ปลายกระบอกเด้งค้างอยู่

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	camera.fov = BASE_FOV

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENS)
		head.rotate_x(-event.relative.y * MOUSE_SENS)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))

	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	# แรงโน้มถ่วง + กระโดด
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = JUMP_VELOCITY

	# ทิศทางที่กด
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	# วิ่ง (อัปเดตเฉพาะตอนอยู่บนพื้น เพื่อคงสถานะกลางอากาศ)
	if is_on_floor():
		is_sprinting = Input.is_action_pressed("sprint") and input_dir.y < -0.1

	var target_speed := SPRINT_SPEED if is_sprinting else WALK_SPEED
	var target_velocity := direction * target_speed
	var accel := GROUND_ACCEL if is_on_floor() else AIR_ACCEL

	velocity.x = move_toward(velocity.x, target_velocity.x, accel * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, accel * delta)

	move_and_slide()

	# FOV
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var fast := is_sprinting and horizontal_speed > WALK_SPEED + 0.5
	var target_fov := SPRINT_FOV if fast else BASE_FOV
	camera.fov = lerpf(camera.fov, target_fov, FOV_SPEED * delta)

	_update_recoil(delta)
	_update_camera_sway(delta, horizontal_speed)

# ---------------------------------------------------------------
# Camera sway
# ---------------------------------------------------------------
func _update_camera_sway(delta: float, horizontal_speed: float) -> void:
	var grounded := is_on_floor()
	var t := Time.get_ticks_msec() / 1000.0

	var target_amp := 0.0
	if grounded:
		target_amp = clampf(horizontal_speed / SPRINT_SPEED, 0.0, 1.0)
	_sway_amp = lerpf(_sway_amp, target_amp, clampf(AMP_SMOOTH * delta, 0.0, 1.0))

	if grounded and horizontal_speed > 0.1:
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
```

### scripts/weapon.gd (แนบที่ Camera3D)

```gdscript
extends Camera3D

@export var max_range: float = 500.0
@export var bullet_speed: float = 250.0   # เมตร/วินาที
@export var damage: float = 50.0
@export var fire_rate: float = 0.35       # วินาทีต่อนัด
@export var impact_scene: PackedScene

@export_group("Recoil")
@export var kick_pitch: float = 6.0     # สะบัดภาพขึ้น จุดสูงสุด (องศา)
@export var kick_yaw: float = 2.4       # ส่ายซ้ายขวาของภาพ ± (องศา)
@export var kick_roll: float = 3.0      # เอียงกล้อง ± (องศา)
@export var aim_pitch: float = 2.0      # ปลายกระบอกเด้งจริงต่อนัด
@export var aim_yaw: float = 0.5        # ปลายกระบอกส่ายจริง ± ต่อนัด
@export var wander: float = 0.6         # 0 = สุ่มล้วน, 1 = เตะไปทางเดิมต่อเนื่อง
@export var recoil_reset_time: float = 0.35

@onready var player: CharacterBody3D = owner

var _cooldown := 0.0
var _since_last_shot := 999.0
var _bias := 0.0   # ทิศที่ปืนกำลังเตะไป (-1..1) เปลี่ยนช้าๆ ระหว่างยิงรัว

func _process(delta: float) -> void:
	_cooldown -= delta
	_since_last_shot += delta
	if Input.is_action_pressed("shoot") \
	and _cooldown <= 0.0 \
	and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_cooldown = fire_rate
		shoot()

func shoot() -> void:
	var space := get_world_3d().direct_space_state
	var from := global_position
	var to := from + -global_transform.basis.z * max_range

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [player.get_rid()]   # exclude ต้องเป็น RID ไม่ใช่ Node
	var result := space.intersect_ray(query)

	# ยิง ray ก่อน แล้วค่อยใส่ recoil (นัดแรกจึงตรงเคอร์เซอร์)
	_fire_recoil()

	if result.is_empty():
		return   # ไม่มีอะไรอยู่ในระยะ = ยิงพลาด

	var hit_pos: Vector3 = result.position
	var hit_normal: Vector3 = result.normal
	var collider_id: int = result.collider.get_instance_id()   # เก็บเป็น ID กัน object ถูก free

	var travel_time := from.distance_to(hit_pos) / bullet_speed
	await get_tree().create_timer(travel_time).timeout

	if not is_inside_tree():
		return
	_apply_hit(collider_id, hit_pos, hit_normal)

func _fire_recoil() -> void:
	# หยุดยิงพักหนึ่ง = ทิศเตะรีเซ็ต
	if _since_last_shot > recoil_reset_time:
		_bias = randf_range(-1.0, 1.0)
	_since_last_shot = 0.0

	# ทิศเตะค่อยๆ เดินสุ่ม ไม่กระโดดมั่ว
	_bias = clampf(_bias + randf_range(-0.5, 0.5), -1.0, 1.0)
	var dir := lerpf(randf_range(-1.0, 1.0), _bias, wander)

	player.apply_recoil(
		kick_pitch * randf_range(0.8, 1.25),
		kick_yaw * dir,
		kick_roll * dir * randf_range(0.6, 1.2),
		aim_pitch * randf_range(0.8, 1.2),
		aim_yaw * dir
	)

func _apply_hit(collider_id: int, pos: Vector3, _normal: Vector3) -> void:
	var collider := instance_from_id(collider_id)
	if is_instance_valid(collider) and collider.has_method("take_damage"):
		collider.take_damage(damage)

	if impact_scene:
		var fx: Node3D = impact_scene.instantiate()
		get_tree().current_scene.add_child(fx)
		fx.global_position = pos
```

**อย่าลืม:** ใน Inspector ของ Camera3D ต้องลาก `impact.tscn` ใส่ช่อง **Impact Scene**

### scripts/crosshair.gd

```gdscript
extends Control

@export var color := Color(1, 1, 1, 0.9)
@export var outline_color := Color(0, 0, 0, 0.6)
@export var gap := 5.0
@export var length := 9.0
@export var thickness := 2.0
@export var show_dot := true

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)

func _draw() -> void:
	var c := size / 2.0
	var dirs := [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]

	for d in dirs:
		draw_line(c + d * (gap - 1.0), c + d * (gap + length + 1.0), outline_color, thickness + 2.0)
	for d in dirs:
		draw_line(c + d * gap, c + d * (gap + length), color, thickness)

	if show_dot:
		draw_circle(c, 1.5, color)
```

### scripts/impact.gd

```gdscript
extends Node3D

func _ready() -> void:
	await get_tree().create_timer(2.0).timeout
	queue_free()
```

### scripts/target.gd

```gdscript
extends StaticBody3D

var hp := 100.0

func take_damage(amount: float) -> void:
	hp -= amount
	print("%s โดนยิง! HP เหลือ %.0f" % [name, hp])
	if hp <= 0:
		queue_free()
```

---

## 4. ระบบที่ทำเสร็จแล้ว

| ระบบ | สถานะ | หมายเหตุ |
|---|---|---|
| เดิน / มองเมาส์ / กระโดด | เสร็จ | Esc ปล่อยเมาส์ คลิกเพื่อจับกลับ |
| Hitscan + หน่วงตามระยะ | เสร็จ | ตรวจตอนยิง ผลแสดงตามเวลา |
| เคอร์เซอร์เล็ง | เสร็จ | วาดด้วยโค้ด ต้องตั้ง Full Rect |
| วิ่ง (Sprint) | เสร็จ | Shift + เดินหน้าเท่านั้น FOV 75→85 มีโมเมนตัม (accel/decel) |
| กล้องโยกตามก้าว (head sway) | เสร็จ | sin/cos วงสวิง ผู้ใช้ **ชอบแล้ว** และตั้งใจให้ยังคงไว้ แม้มันทำให้วิ่งยิงยาก (ผู้ใช้ต้องการให้วิ่งยิงยากอยู่แล้ว ห้ามตัด yaw/pitch ออกเอง) |
| Recoil แบบสปริง | เสร็จ | แยกสองชั้น: kick (ภาพ) และ aim recoil (จุดเล็งจริง) |
| ชุดค่า Desert Eagle | ใช้อยู่ | ยิงช้า นัดหนัก สะบัดแรง |

---

## 5. ปัญหาที่เคยเจอ และวิธีแก้ (กันพลาดซ้ำ)

1. **`query.exclude` ต้องเป็น `Array[RID]`** ใช้ `player.get_rid()` ไม่ใช่ Node
2. **Error "Invalid type in function '_apply_hit'... previously freed"**: เกิดเมื่อเป้าถูก `queue_free()` ระหว่างกระสุนค้างหน่วงเวลา แก้โดยส่ง `collider` เป็น **instance ID** (int) แล้วใช้ `instance_from_id()` ตอนใช้งาน
3. **เคอร์เซอร์ไปอยู่มุมซ้ายบน**: Control ยังไม่ Full Rect แก้ด้วย `set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)` ใน `_ready()`
4. **ย่อหน้าผิดเวลาคัดลอกโค้ด**: เคยเจอ `var hit_pos` ย่อหน้าเข้าไปใต้ `return` ต้องตรวจย่อหน้าเสมอ
5. **กล้องส่ายแบบแข็ง/หักไปมา**: แก้โดยคำนวณจากเฟส sin/cos โดยตรง แล้ว lerp เฉพาะ "ขนาดการส่าย" ไม่ lerp ตำแหน่งไล่เป้า
6. **Recoil สะบัดน้อย**: สูตร lerp เข้าหา 0 ไม่มีแรงส่ง จึงเปลี่ยนเป็นสปริง (impulse → velocity → position)
7. **ค่า `@export` ในโค้ดถูก Inspector ทับ**: ถ้าเคยแก้ใน Inspector ค่าจะไม่เปลี่ยนตามโค้ด ต้องรีเซ็ตที่ Inspector
8. **เกมฝังใน editor หน้าต่างเล็ก** (Godot 4.4+): ปรับผ่านเมนู ⋮ ที่แถบขวาบน หรือปิด Embed Game

---

## 6. Roadmap / ไอเดียที่ยังไม่ได้ทำ

ลำดับที่แนะนำไว้:

1. **Tracer**: เส้นแสง/หัวกระสุนวิ่งจากปากกระบอกไปจุดโดนตามเวลาหน่วง (tween mesh เล็กๆ ไม่ต้องใช้ physics) ให้ยิงพลาดก็วิ่งไปสุดระยะ (`max_range`) แล้วหาย ในโค้ดเคยวาง stub `spawn_tracer(from, to, duration)` ไว้ ปัจจุบันยังไม่มีใน weapon.gd
2. **Muzzle flash + เสียงยิง**: เสียงกระทบมาช้ากว่าภาพตามระยะ
3. **ระบบย่อ (Crouch)** และ **สไลด์ (Slide)**: ผู้ใช้ระบุพฤติกรรมไว้ว่า: วิ่งอยู่แล้วกดย่อค้าง → สไลด์ตามความเร็วที่มี (โมเมนตัมค่อยๆ ลดจากแรงเสียดทาน) → เมื่อความเร็วลดพอ กลายเป็นย่อปกติ ต้องทำ:
   - เพิ่ม action `crouch`
   - ลดความสูง CapsuleShape3D และตำแหน่ง Head ตามสถานะ (ใช้ RayCast ตรวจเพดานก่อนลุก)
   - อ่านค่า `is_sprinting` และ velocity ตอนเริ่มสไลด์ เพื่อเอาความเร็วตั้งต้น
   - การเคลื่อนที่ปัจจุบันเป็นแบบ accel/decel (`move_toward`) ไว้ให้รองรับสไลด์แล้ว
   - อาจให้ยิงตอนสไลด์แม่นกว่าตอนวิ่ง
4. **Spread ตามการเคลื่อนไหว + เคอร์เซอร์ขยาย**: วิ่งยิงกระจาย ยืน/ย่อแม่นขึ้น
5. **Recoil pattern** (ลวดลายแรงดีดคงที่ต่อปืน) แทนสุ่มล้วน
6. **เล็งนำเป้า (lead the target)**: ตัดสินใจว่าจะเปลี่ยนไป "ตรวจ raycast ตอนกระสุนถึงจริง" (เก็บ ray แล้วตรวจซ้ำ หรือจำลองกระสุนเป็น struct ใน array แล้วเดิน raycast ทีละช่วงต่อเฟรม = Hybrid Simulated Ballistics) เพื่อให้เป้าหลบได้และเกิด bullet drop ได้ ซึ่งเป็นจุดขายของเกมได้
7. ระบบ HP/ศัตรู/ตัวเป้าจริง, ระบบอาวุธหลายกระบอก (แยกค่าเป็น Resource), ตัวเลือกลด/ปิดกล้องส่ายในเมนูตั้งค่า (มี `sway_intensity` เตรียมไว้แล้ว)

### ไอเดียแมคคานิคที่เสนอไปเพิ่ม (ผู้ใช้เปิดรับ)

- Slide ยิงแม่นกว่าวิ่ง เป็นรางวัลของการเคลื่อนไหวเก่ง
- Tracer + เสียงหน่วงตามระยะ ให้ระบบหน่วงเวลามีเอกลักษณ์
- ยิงเป้าไกลต้องเล็งนำ (ถ้าเลือกตรวจตอนกระสุนถึง)

---

## 7. ความชอบของผู้ใช้ (สรุป)

- ตอบภาษาไทย กระชับ เป็นขั้นตอน
- ขอ **สคริปต์ทั้งไฟล์** ทุกครั้งที่มีการแก้ (เคยขอย้ำหลายรอบ)
- อยากได้เกมแนวแอคชั่นเร็ว ฟีลปืนหนักแน่นสมจริง
- วิ่งยิงควร "ยาก" เป็นเรื่องปกติของเกม ไม่ต้องแก้ให้ง่ายขึ้น
- ชอบให้ Claude เสนอไอเดียและร่วมคิด ไม่ใช่รับคำสั่งอย่างเดียว
- ผู้ใช้ทดสอบเองแล้วรายงานฟีล เช่น "สะบัดน้อยไป" ให้ปรับเป็นค่าตัวเลขแล้วอธิบายว่าปรับตัวไหนได้อีก

---

## 8. ขั้นต่อไปที่แนะนำให้เริ่ม

เริ่มจาก **ระบบย่อ (Crouch)** แล้วต่อด้วย **สไลด์** ตามที่ผู้ใช้วางแผนไว้ (ผู้ใช้เคยบอกว่าเริ่มที่วิ่งก่อน ซึ่งเสร็จแล้ว) หรือทำ **Tracer** ก่อนถ้าอยากเห็นผลของการหน่วงเวลาชัดขึ้น ควรถามผู้ใช้ว่าอยากเริ่มข้อไหน และส่ง `player.gd` ฉบับเต็มกลับไปทุกครั้งที่แก้

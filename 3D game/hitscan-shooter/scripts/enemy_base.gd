class_name EnemyBase
extends CharacterBody3D

# ตัวแม่ของมอนทุกแบบ: HP, เก่งขึ้นตาม Wave, รับดาเมจ, ตาย, หาผู้เล่น
# - ตัวลูก override _think() เพื่อกำหนดพฤติกรรม
# - ตัวลูก override _build_visual(root) เพื่อสร้างโมเดล และ _animate(delta) เพื่อขยับแขนขา
# - collision สร้างจากโค้ด ใน scene ใส่แค่ node CharacterBody3D + สคริปต์ก็พอ
# - มอนที่ยังมีชีวิตอยู่อยู่ใน group "enemies" (ไว้นับจำนวนใน Wave HUD)
# - ตายแล้วส่ง signal died (ไว้ทำของดรอป/นับ Wave)
#
# วัสดุที่ตัวลูกใช้ได้ใน _build_visual:
#   _mat   = เปลือกหลัก (กะพริบขาวตอนโดนยิง)
#   _plate = เปลือกส่วนเกราะ/กรงเล็บ (สีเข้มกว่า)
#   _glow  = เส้นพลังงาน/ตา/ผลึก (เรืองแรงขึ้นตอนง้างโจมตี)
#
# ค่าให้ตัวลูกอ่านใน _animate:
#   _walk_phase = เฟสก้าวเดิน, _move_amt = 0..1 เดินเร็วแค่ไหน
#   _tele = 0..1 ความคืบหน้าท่าง้าง (ใช้ยกแขน), _strike = 1..0 แรงสะบัดหลังโจมตี
#   _t = เวลาสะสม (ไว้ทำหายใจ)

signal died(enemy: Node3D)

@export_group("Stats (ที่ Wave 1)")
@export var max_hp := 100.0
@export var move_speed := 5.0
@export var damage := 10.0

@export_group("เก่งขึ้นตาม Wave (ต่อ 1 Wave)")
@export var hp_growth := 0.25        # +25% HP ต่อ Wave
@export var speed_growth := 0.03     # +3% ความเร็วต่อ Wave
@export var damage_growth := 0.15    # +15% ดาเมจต่อ Wave
@export var max_speed_mult := 1.6    # เพดานความเร็ว (กันเร็วเกินจนหนีไม่ได้)

@export_group("รูปร่าง")
@export var body_color := Color(0.85, 0.2, 0.2)   # สีหลักของมอน (เปลือกจะเป็นสีเดียวกันแต่เข้มลง)
@export var glow_color := Color(1.0, 0.3, 0.15)   # สีเส้นพลังงาน/ตา
@export var body_height := 1.8                    # ขนาด collision
@export var body_radius := 0.5

const ACCEL := 30.0
const TURN_SPEED := 10.0

var wave := 1           # Spawner เรียก set_wave() ก่อน add_child
var hp := 0.0
var speed := 0.0
var attack_damage := 0.0
var target: Node3D

var _dead := false
var _mat: StandardMaterial3D
var _plate: StandardMaterial3D
var _glow: StandardMaterial3D
var _shell_color := Color.WHITE
var _plate_color := Color.WHITE
var _model: Node3D
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var _t := 0.0
var _phase_off := randf() * TAU
var _walk_phase := 0.0
var _move_amt := 0.0
var _tele := 0.0
var _tele_color := Color.WHITE
var _strike := 0.0

func set_wave(w: int) -> void:
	wave = maxi(w, 1)

func _ready() -> void:
	add_to_group("enemies")

	var w := wave - 1
	hp = max_hp * (1.0 + hp_growth * w)
	speed = move_speed * minf(1.0 + speed_growth * w, max_speed_mult)
	attack_damage = damage * (1.0 + damage_growth * w)

	_build_body()
	_find_target()
	_setup()

func _physics_process(delta: float) -> void:
	if _dead:
		return

	if not is_on_floor():
		velocity.y -= _gravity * delta

	if not is_instance_valid(target):
		_find_target()

	if _target_alive():
		_think(delta)
	else:
		_move_dir(Vector3.ZERO, 0.0, delta)   # ผู้เล่นตายแล้ว: หยุดยืน

	move_and_slide()

func _process(delta: float) -> void:
	if _dead or _model == null:
		return
	_t += delta

	var hs := Vector2(velocity.x, velocity.z).length()
	_move_amt = lerpf(_move_amt, clampf(hs / maxf(speed, 0.1), 0.0, 1.0), clampf(10.0 * delta, 0.0, 1.0))
	if hs > 0.1:
		_walk_phase = fmod(_walk_phase + delta * (2.5 + hs * 1.3), TAU)
	_strike = move_toward(_strike, 0.0, delta * 4.0)

	# ตัวโยกตามก้าว
	_model.position.y = absf(sin(_walk_phase)) * 0.07 * _move_amt
	_model.rotation.z = sin(_walk_phase) * 0.04 * _move_amt

	# แสงพลังงาน: หายใจเบาๆ ตลอด / ตอนง้างโจมตีสว่างแรงและเปลี่ยนเป็นสีเตือน
	_glow.emission = glow_color.lerp(_tele_color, _tele)
	_glow.emission_energy_multiplier = 2.0 + sin(_t * 3.0 + _phase_off) * 0.4 + _tele * 5.0
	_mat.emission = _tele_color
	_mat.emission_energy_multiplier = _tele * 1.5

	_animate(delta)

# ---------------------------------------------------------------
# ให้ตัวลูก override
# ---------------------------------------------------------------
func _setup() -> void:
	pass

func _think(_delta: float) -> void:
	pass

func _on_death() -> void:
	pass

# สร้างโมเดลใต้ root (จุดกำเนิด = เท้า, หน้ามอน = แกน -Z)
# ค่าเริ่มต้น: แคปซูลเรียบๆ (ตัวลูกที่ไม่ override จะเห็นแบบนี้)
func _build_visual(root: Node3D) -> void:
	var mesh := CapsuleMesh.new()
	mesh.radius = body_radius
	mesh.height = body_height
	mesh.material = _mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position.y = body_height * 0.5
	root.add_child(mi)

	var nose_mesh := BoxMesh.new()
	nose_mesh.size = Vector3(0.3, 0.3, 0.4)
	nose_mesh.material = _plate
	var nose := MeshInstance3D.new()
	nose.mesh = nose_mesh
	nose.position = Vector3(0.0, body_height * 0.72, -body_radius)
	root.add_child(nose)

# ขยับแขนขา (เรียกทุกเฟรมหลังคำนวณค่ากลางเสร็จ)
func _animate(_delta: float) -> void:
	pass

# ---------------------------------------------------------------
# ดาเมจ / ตาย
# ---------------------------------------------------------------
func take_damage(amount: float) -> void:
	if _dead:
		return
	hp -= amount
	_flash()
	if hp <= 0.0:
		_die()

func _die() -> void:
	_dead = true
	collision_layer = 0   # กระสุนที่ยังค้างอยู่จะไม่ชนอีก
	collision_mask = 0
	velocity = Vector3.ZERO
	remove_from_group("enemies")   # ให้ตัวนับมอนลดทันที
	_on_death()
	died.emit(self)

	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE * 0.01, 0.2)
	tw.tween_callback(queue_free)

# ---------------------------------------------------------------
# ตัวช่วยสำหรับตัวลูก
# ---------------------------------------------------------------
func _target_alive() -> bool:
	return is_instance_valid(target) and not target.get("is_dead")

func _flat_to_target() -> Vector3:
	var d := target.global_position - global_position
	d.y = 0.0
	return d

func _move_dir(dir: Vector3, spd: float, delta: float) -> void:
	velocity.x = move_toward(velocity.x, dir.x * spd, ACCEL * delta)
	velocity.z = move_toward(velocity.z, dir.z * spd, ACCEL * delta)

func _face(dir: Vector3, delta: float) -> void:
	if dir.length() < 0.01:
		return
	var yaw := atan2(-dir.x, -dir.z)   # หน้ามอน = แกน -Z
	rotation.y = lerp_angle(rotation.y, yaw, clampf(TURN_SPEED * delta, 0.0, 1.0))

func _flash() -> void:
	_mat.albedo_color = Color.WHITE
	_plate.albedo_color = Color.WHITE
	var tw := create_tween()
	tw.tween_property(_mat, "albedo_color", _shell_color, 0.12)
	tw.parallel().tween_property(_plate, "albedo_color", _plate_color, 0.12)

# ท่าง้าง: ตัวเรืองสีค่อยๆ สว่างขึ้น (_tele วิ่ง 0 -> 1) = เตือนผู้เล่นว่ากำลังจะโจมตี
# จบท่าแล้ว _tele กลับ 0 และ _strike = 1 (ตัวลูกใช้ทำท่าสะบัดโจมตี)
func _telegraph(color: Color, duration: float) -> void:
	_tele_color = color
	var tw := create_tween()
	tw.tween_method(_set_tele, 0.0, 1.0, duration)
	tw.tween_callback(_end_telegraph)

func _set_tele(v: float) -> void:
	_tele = v

func _end_telegraph() -> void:
	_tele = 0.0
	_strike = 1.0

# ---------------------------------------------------------------
# สร้างตัว / หาผู้เล่น
# ---------------------------------------------------------------
func _find_target() -> void:
	target = get_tree().get_first_node_in_group("player") as Node3D
	if target == null:
		target = get_tree().current_scene.find_child("Player", true, false) as Node3D

func _build_body() -> void:
	if get_node_or_null("CollisionShape3D") == null:
		var shape := CapsuleShape3D.new()
		shape.radius = body_radius
		shape.height = body_height
		var col := CollisionShape3D.new()
		col.name = "CollisionShape3D"
		col.shape = shape
		col.position.y = body_height * 0.5   # จุดกำเนิด = เท้า
		add_child(col)

	_shell_color = body_color.darkened(0.4)
	_plate_color = body_color.darkened(0.7)
	_mat = AlienBuilder.shell_material(_shell_color)
	_plate = AlienBuilder.shell_material(_plate_color, 0.35, 0.5)
	_glow = AlienBuilder.glow_material(glow_color)
	_tele_color = glow_color

	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	_build_visual(_model)

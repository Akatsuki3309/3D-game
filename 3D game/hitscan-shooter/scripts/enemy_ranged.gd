class_name EnemyRanged
extends EnemyBase

# มอนตีไกล "เอเลี่ยนพลาสม่า": ตัวผอมสูง หัวมีสันยาว แขนขวาเป็นปืนใหญ่พลาสม่า
# รักษาระยะ เดินวนซ้ายขวา ถอยถ้าถูกเข้าใกล้ ยิงกระสุนช้าที่หลบได้
# ก่อนยิงปากกระบอกเรืองและยกปืนเล็ง ยิงไปที่ตำแหน่งผู้เล่น "ตอนยิง" ไม่ได้เล็งนำ จึงหลบด้วยการเคลื่อนที่ได้

@export var preferred_range := 14.0
@export var min_range := 8.0          # เข้าใกล้กว่านี้จะถอย
@export var shoot_range := 30.0
@export var projectile_speed := 16.0  # เมตร/วินาที
@export var windup := 0.5
@export var fire_cooldown := 2.0

var _cd := 1.0
var _winding := false
var _strafe := 1.0
var _strafe_timer := 0.0

var _legs: Array[Node3D] = []   # [ซ้าย, ขวา]
var _arm_l: Node3D
var _arm_cannon: Node3D
var _tip: MeshInstance3D
var _pose := 0.0

func _init() -> void:
	body_color = Color(0.25, 0.5, 0.95)
	glow_color = Color(0.2, 0.95, 1.0)
	max_hp = 70.0
	move_speed = 4.5
	damage = 12.0

func _setup() -> void:
	_cd = randf_range(0.5, fire_cooldown)   # กันมอนทั้งฝูงยิงพร้อมกัน
	_strafe = -1.0 if randf() < 0.5 else 1.0

func _think(delta: float) -> void:
	_cd -= delta

	var to := _flat_to_target()
	var dist := to.length()
	var dir := to.normalized()
	_face(dir, delta)

	if _winding:
		_move_dir(Vector3.ZERO, 0.0, delta)
		return

	_strafe_timer -= delta
	if _strafe_timer <= 0.0:
		_strafe_timer = randf_range(1.5, 3.0)
		_strafe = -_strafe

	var move := Vector3.ZERO
	var spd := speed
	if dist > preferred_range + 2.0:
		move = dir
	elif dist < min_range:
		move = -dir
		spd = speed * 0.8
	else:
		move = dir.cross(Vector3.UP).normalized() * _strafe
		spd = speed * 0.5
	_move_dir(move, spd, delta)

	if _cd <= 0.0 and dist <= shoot_range:
		_fire()

func _fire() -> void:
	_winding = true
	_telegraph(Color(1.0, 0.9, 0.2), windup)

	await get_tree().create_timer(windup, false).timeout
	if _dead or not is_inside_tree():
		return

	_winding = false
	_cd = fire_cooldown
	if not _target_alive():
		return

	var origin := global_position + Vector3(0.0, body_height * 0.7, 0.0)
	var dir := (target.global_position - origin).normalized()

	var p := EnemyProjectile.new()
	get_tree().current_scene.add_child(p)
	p.global_position = origin
	p.setup(self, dir * projectile_speed, attack_damage)

# ---------------------------------------------------------------
# โมเดล (หน้า = -Z, เท้าอยู่ y = 0)
# ---------------------------------------------------------------
func _build_visual(root: Node3D) -> void:
	var shell := _mat
	var plate := _plate
	var glow := _glow

	# สะโพก + ลำตัวเรียว
	AlienBuilder.ellipsoid(root, Vector3(0.0, 0.85, 0.0), Vector3(0.2, 0.17, 0.18), plate)
	AlienBuilder.ellipsoid(root, Vector3(0.0, 1.2, -0.02), Vector3(0.23, 0.4, 0.19), shell)

	# ถุงพลังงานบนหลัง + ท่อต่อไปที่แขนปืน
	AlienBuilder.ellipsoid(root, Vector3(0.0, 1.3, 0.26), Vector3(0.13, 0.2, 0.13), glow)
	AlienBuilder.ellipsoid(root, Vector3(0.0, 1.3, 0.2), Vector3(0.17, 0.24, 0.1), plate)
	AlienBuilder.tube(root,
		PackedVector3Array([Vector3(0.05, 1.35, 0.2), Vector3(0.2, 1.45, 0.08), Vector3(0.27, 1.4, -0.02)]),
		PackedFloat32Array([0.025, 0.022, 0.02]), glow, 5, 6, "ranged_hose")

	# คอ + หัวยาวเรียว + ตาแถบเดียว + สันหัว
	AlienBuilder.tube(root,
		PackedVector3Array([Vector3(0.0, 1.5, 0.0), Vector3(0.0, 1.62, -0.07)]),
		PackedFloat32Array([0.07, 0.06]), shell, 4, 8, "ranged_neck")
	AlienBuilder.ellipsoid(root, Vector3(0.0, 1.72, -0.12), Vector3(0.14, 0.16, 0.26), shell, Vector3(-10.0, 0.0, 0.0))
	AlienBuilder.ellipsoid(root, Vector3(0.0, 1.74, -0.36), Vector3(0.1, 0.045, 0.05), glow)
	AlienBuilder.tube(root,
		PackedVector3Array([Vector3(0.0, 1.82, -0.02), Vector3(0.0, 1.98, 0.22), Vector3(0.0, 1.85, 0.5)]),
		PackedFloat32Array([0.05, 0.04, 0.004]), plate, 6, 8, "ranged_crest")

	# ขายาวเรียว
	var leg_ctrl := PackedVector3Array([
		Vector3(0.0, 0.0, 0.0), Vector3(0.0, -0.3, -0.16),
		Vector3(0.0, -0.55, 0.1), Vector3(0.0, -0.84, -0.05)])
	var leg_r := PackedFloat32Array([0.06, 0.047, 0.035, 0.02])
	for side in [-1.0, 1.0]:
		var hip := AlienBuilder.pivot(root, Vector3(side * 0.12, 0.85, 0.0))
		AlienBuilder.tube(hip, leg_ctrl, leg_r, shell, 6, 8, "ranged_leg")
		AlienBuilder.ellipsoid(hip, Vector3(0.0, -0.83, -0.1), Vector3(0.04, 0.02, 0.1), plate)
		_legs.append(hip)

	# แขนซ้าย: ห้อยเรียว ปลายเป็นกรงเล็บ
	_arm_l = AlienBuilder.pivot(root, Vector3(-0.27, 1.4, -0.02))
	AlienBuilder.tube(_arm_l,
		PackedVector3Array([Vector3(0.0, 0.0, 0.0), Vector3(-0.05, -0.25, -0.05),
			Vector3(-0.05, -0.5, -0.2), Vector3(-0.03, -0.62, -0.38)]),
		PackedFloat32Array([0.04, 0.032, 0.026, 0.004]), plate, 6, 8, "ranged_arm_l")

	# แขนขวา: ปืนใหญ่พลาสม่า
	_arm_cannon = AlienBuilder.pivot(root, Vector3(0.27, 1.4, -0.02))
	AlienBuilder.ellipsoid(_arm_cannon, Vector3.ZERO, Vector3(0.09, 0.09, 0.09), plate)
	AlienBuilder.tube(_arm_cannon,
		PackedVector3Array([Vector3(0.0, 0.0, 0.0), Vector3(0.04, -0.1, -0.2), Vector3(0.04, -0.12, -0.45)]),
		PackedFloat32Array([0.05, 0.07, 0.065]), shell, 6, 10, "ranged_cannon")
	AlienBuilder.tube(_arm_cannon,
		PackedVector3Array([Vector3(0.04, -0.12, -0.45), Vector3(0.04, -0.12, -0.75)]),
		PackedFloat32Array([0.04, 0.025]), plate, 4, 8, "ranged_barrel")
	_tip = AlienBuilder.ellipsoid(_arm_cannon, Vector3(0.04, -0.12, -0.77), Vector3(0.045, 0.045, 0.045), glow)

func _animate(delta: float) -> void:
	var swing := sin(_walk_phase) * 0.6 * _move_amt
	_legs[0].rotation.x = swing
	_legs[1].rotation.x = -swing
	_arm_l.rotation.x = -swing * 0.8 + sin(_t * 1.5) * 0.03

	# ยกปืนเล็งตอนง้าง ปืนสะบัดขึ้นตอนยิง ปากกระบอกบวมตามพลังงานที่สะสม
	_pose = lerpf(_pose, _tele, clampf(14.0 * delta, 0.0, 1.0))
	_arm_cannon.rotation.x = 0.1 + _pose * 0.55 + _strike * 0.35 + swing * 0.15
	var s := 1.0 + _tele * 1.3 + _strike * 0.6
	_tip.scale = Vector3(0.045, 0.045, 0.045) * s

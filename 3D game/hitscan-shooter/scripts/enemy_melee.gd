class_name EnemyMelee
extends EnemyBase

# มอนตีใกล้ "เอเลี่ยนเคียว": ตัวค่อมๆ ขาพับกลับ แขนสองข้างเป็นเคียวแหลม
# วิ่งเข้าหา พอถึงระยะจะยกเคียวขึ้นเหนือหัว (ตัวเรืองแดง) แล้วฟันลง
# ผู้เล่นถอยหลบทันในช่วงง้างได้

@export var attack_range := 1.9       # ระยะที่เริ่มง้าง (วัดจากจุดกึ่งกลางตัว)
@export var windup := 0.4             # เวลาง้างก่อนตีจริง
@export var attack_cooldown := 1.0
@export var hit_tolerance := 0.6      # ตอนตีจริง ผู้เล่นต้องอยู่ในระยะ + ค่านี้ ถึงจะโดน

var _cd := 0.0
var _winding := false

var _legs: Array[Node3D] = []   # [ซ้าย, ขวา]
var _arms: Array[Node3D] = []   # [ซ้าย, ขวา]
var _pose := 0.0                # ท่ายกแขน (smooth)

func _init() -> void:
	body_color = Color(0.85, 0.2, 0.2)
	glow_color = Color(1.0, 0.25, 0.12)
	max_hp = 100.0
	move_speed = 5.5
	damage = 15.0

func _think(delta: float) -> void:
	_cd -= delta

	var to := _flat_to_target()
	var dist := to.length()
	var dir := to.normalized()
	_face(dir, delta)

	if _winding:
		_move_dir(Vector3.ZERO, 0.0, delta)
		return

	if dist > attack_range:
		_move_dir(dir, speed, delta)
	else:
		_move_dir(Vector3.ZERO, 0.0, delta)
		if _cd <= 0.0:
			_attack()

func _attack() -> void:
	_winding = true
	_telegraph(Color(1.0, 0.2, 0.1), windup)

	await get_tree().create_timer(windup, false).timeout
	if _dead or not is_inside_tree():
		return

	_winding = false
	_cd = attack_cooldown
	if _target_alive() and _flat_to_target().length() <= attack_range + hit_tolerance:
		target.take_damage(attack_damage)

# ---------------------------------------------------------------
# โมเดล (หน้า = -Z, เท้าอยู่ y = 0)
# ---------------------------------------------------------------
func _build_visual(root: Node3D) -> void:
	var shell := _mat
	var plate := _plate
	var glow := _glow

	# ลำตัวค่อมไปข้างหน้า + โหนกหลัง
	AlienBuilder.ellipsoid(root, Vector3(0.0, 1.1, 0.05), Vector3(0.36, 0.4, 0.52), shell, Vector3(-18.0, 0.0, 0.0))
	AlienBuilder.ellipsoid(root, Vector3(0.0, 1.38, 0.3), Vector3(0.28, 0.3, 0.36), plate)
	AlienBuilder.ellipsoid(root, Vector3(0.0, 0.85, 0.1), Vector3(0.3, 0.2, 0.28), plate)

	# หนามสันหลัง
	for i in 4:
		var base := Vector3(0.0, 1.62 - i * 0.08, 0.12 + i * 0.17)
		AlienBuilder.cone(root, base, Vector3(0.0, 1.0, 0.55), 0.055, 0.32 - i * 0.04, plate)

	# เส้นพลังงานข้างลำตัว
	for side in [-1.0, 1.0]:
		var vein := PackedVector3Array([
			Vector3(side * 0.31, 1.3, -0.25), Vector3(side * 0.36, 1.12, 0.0),
			Vector3(side * 0.32, 0.98, 0.3)])
		AlienBuilder.tube(root, vein, PackedFloat32Array([0.012, 0.014, 0.01]), glow, 5, 6,
			"melee_vein_%d" % int(side))

	# คอ + หัว + ตา + ขากรรไกร
	AlienBuilder.tube(root,
		PackedVector3Array([Vector3(0.0, 1.25, -0.25), Vector3(0.0, 1.34, -0.5)]),
		PackedFloat32Array([0.14, 0.11]), shell, 4, 10, "melee_neck")
	AlienBuilder.ellipsoid(root, Vector3(0.0, 1.36, -0.66), Vector3(0.2, 0.17, 0.3), shell, Vector3(12.0, 0.0, 0.0))
	for side in [-1.0, 1.0]:
		AlienBuilder.ellipsoid(root, Vector3(side * 0.11, 1.42, -0.88), Vector3(0.045, 0.04, 0.06), glow)
		var jaw := PackedVector3Array([
			Vector3(side * 0.07, 1.27, -0.88), Vector3(side * 0.15, 1.17, -1.02),
			Vector3(side * 0.07, 1.1, -1.16)])
		AlienBuilder.tube(root, jaw, PackedFloat32Array([0.026, 0.02, 0.004]), plate, 5, 6,
			"melee_jaw_%d" % int(side))

	# ขา (ขาพับกลับแบบสัตว์ สองข้างรูปเดียวกัน)
	var leg_ctrl := PackedVector3Array([
		Vector3(0.0, 0.0, 0.0), Vector3(0.0, -0.25, -0.2),
		Vector3(0.0, -0.55, 0.1), Vector3(0.0, -0.84, -0.08)])
	var leg_r := PackedFloat32Array([0.11, 0.085, 0.055, 0.03])
	for side in [-1.0, 1.0]:
		var hip := AlienBuilder.pivot(root, Vector3(side * 0.24, 0.85, 0.12))
		AlienBuilder.tube(hip, leg_ctrl, leg_r, shell, 6, 10, "melee_leg")
		AlienBuilder.ellipsoid(hip, Vector3(0.0, -0.83, -0.12), Vector3(0.07, 0.03, 0.14), plate)
		_legs.append(hip)

	# แขนเคียว (ซ้าย / ขวา)
	for side in [-1.0, 1.0]:
		var sh := AlienBuilder.pivot(root, Vector3(side * 0.4, 1.3, -0.2))
		var ctrl := PackedVector3Array([
			Vector3(0.0, 0.0, 0.0), Vector3(side * 0.1, -0.12, -0.3),
			Vector3(side * 0.18, -0.1, -0.62), Vector3(side * 0.14, 0.0, -0.95),
			Vector3(0.0, 0.06, -1.2)])
		AlienBuilder.tube(sh, ctrl, PackedFloat32Array([0.1, 0.085, 0.07, 0.04, 0.004]),
			plate, 6, 10, "melee_arm_%d" % int(side))
		AlienBuilder.ellipsoid(sh, Vector3(side * 0.1, -0.12, -0.3), Vector3(0.1, 0.09, 0.1), shell)
		AlienBuilder.ellipsoid(sh, Vector3(0.0, 0.06, -1.17), Vector3(0.012, 0.012, 0.02), glow)
		_arms.append(sh)

func _animate(delta: float) -> void:
	var swing := sin(_walk_phase) * 0.7 * _move_amt
	_legs[0].rotation.x = swing
	_legs[1].rotation.x = -swing

	# ท่าง้าง: ยกเคียวขึ้นเหนือหัว แล้วจบท่าฟันลงแรงๆ
	_pose = lerpf(_pose, _tele, clampf(18.0 * delta, 0.0, 1.0))
	for i in _arms.size():
		var sgn := 1.0 if i == 0 else -1.0
		var idle := sgn * sin(_walk_phase) * 0.3 * _move_amt + 0.1 + sin(_t * 1.8 + float(i)) * 0.04
		_arms[i].rotation.x = lerpf(idle, 1.4, _pose) - _strike * 1.5

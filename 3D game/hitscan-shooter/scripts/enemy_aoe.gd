class_name EnemyAOE
extends EnemyBase

# มอน AOE "ไททันผลึก": ตัวใหญ่ อึด ช้า มีผลึกพลังงานงอกบนหลังและแกนเรืองกลางอก
# เดินเข้ามาถึงระยะแล้วหยุด ยกแขนทั้งสองเหนือหัว ร่ายวงแดงบนพื้น "ตรงที่ผู้เล่นยืนตอนนั้น"
# วงค่อยๆ เต็ม แล้วทุบลง ระเบิดหลังหน่วงเวลา
# ผู้เล่นวิ่งออกนอกวงทันก่อนระเบิด = ไม่โดน (ระเบิดแรงกว่าการตีธรรมดา)

@export var cast_range := 8.0
@export var aoe_radius := 4.0
@export var windup := 0.4             # ท่าร่ายก่อนวงจะปรากฏ
@export var blast_delay := 1.3        # วงแดงค้างกี่วินาทีก่อนระเบิด
@export var cooldown := 3.5
@export var blast_damage_mult := 2.0  # คูณจากดาเมจปกติของมอน

var _cd := 1.0
var _casting := false
var _marker: Node3D
var _inner_mat: StandardMaterial3D

var _legs: Array[Node3D] = []   # [ซ้าย, ขวา]
var _arms: Array[Node3D] = []   # [ซ้าย, ขวา]
var _pose := 0.0

func _init() -> void:
	body_color = Color(0.6, 0.25, 0.85)
	glow_color = Color(0.85, 0.3, 1.0)
	body_height = 2.2
	body_radius = 0.7
	max_hp = 200.0
	move_speed = 3.2
	damage = 15.0

func _think(delta: float) -> void:
	_cd -= delta

	var to := _flat_to_target()
	var dist := to.length()
	var dir := to.normalized()
	_face(dir, delta)

	if _casting:
		_move_dir(Vector3.ZERO, 0.0, delta)
		return

	if dist > cast_range:
		_move_dir(dir, speed, delta)
	else:
		_move_dir(Vector3.ZERO, 0.0, delta)
		if _cd <= 0.0:
			_cast()

func _cast() -> void:
	_casting = true
	_telegraph(Color(0.8, 0.3, 1.0), windup + blast_delay)

	await get_tree().create_timer(windup, false).timeout
	if _dead or not is_inside_tree():
		return
	if not _target_alive():
		_casting = false
		return

	var center := target.global_position
	center.y = global_position.y + 0.04   # วางที่ระดับพื้นที่มอนยืน
	_spawn_marker(center)

	await get_tree().create_timer(blast_delay, false).timeout
	if _dead or not is_inside_tree():
		return
	_explode(center)

func _spawn_marker(center: Vector3) -> void:
	_marker = Node3D.new()
	_marker.top_level = true   # อยู่ในพิกัดโลก ไม่ตามตัวมอน แต่ถูกลบพร้อมมอน
	add_child(_marker)
	_marker.global_position = center

	var outer := _make_disc(Color(1.0, 0.1, 0.1, 0.25))
	_marker.add_child(outer.mesh_instance)

	var inner := _make_disc(Color(1.0, 0.15, 0.1, 0.5))
	inner.mesh_instance.position.y = 0.02
	inner.mesh_instance.scale = Vector3(0.02, 1.0, 0.02)
	_marker.add_child(inner.mesh_instance)
	_inner_mat = inner.material

	# วงในขยายเต็มวงนอก = นับถอยหลังระเบิด
	var tw: Tween = inner.mesh_instance.create_tween()
	tw.tween_property(inner.mesh_instance, "scale", Vector3.ONE, blast_delay)

func _make_disc(color: Color) -> Dictionary:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var mesh := CylinderMesh.new()
	mesh.top_radius = aoe_radius
	mesh.bottom_radius = aoe_radius
	mesh.height = 0.04
	mesh.material = mat

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return {"mesh_instance": mi, "material": mat}

func _explode(center: Vector3) -> void:
	_casting = false
	_cd = cooldown

	if _target_alive():
		var d := target.global_position - center
		d.y = 0.0
		if d.length() <= aoe_radius:
			target.take_damage(attack_damage * blast_damage_mult)

	if is_instance_valid(_marker):
		_inner_mat.albedo_color = Color(1.0, 0.9, 0.6, 0.9)   # วาบตอนระเบิด
		var tw := _marker.create_tween()
		tw.tween_property(_marker, "scale", Vector3(1.15, 1.0, 1.15), 0.2)
		tw.tween_callback(_marker.queue_free)

func _on_death() -> void:
	if is_instance_valid(_marker):
		_marker.queue_free()   # ตายกลางร่าย = วงหายไม่ระเบิด

# ---------------------------------------------------------------
# โมเดล (หน้า = -Z, เท้าอยู่ y = 0)
# ---------------------------------------------------------------
func _build_visual(root: Node3D) -> void:
	var shell := _mat
	var plate := _plate
	var glow := _glow

	# ลำตัวใหญ่ + เกราะไหล่ + แกนพลังงานกลางอก
	AlienBuilder.ellipsoid(root, Vector3(0.0, 1.25, 0.0), Vector3(0.75, 0.65, 0.62), shell, Vector3(-8.0, 0.0, 0.0))
	AlienBuilder.ellipsoid(root, Vector3(0.0, 0.95, 0.05), Vector3(0.55, 0.3, 0.45), plate)
	AlienBuilder.ellipsoid(root, Vector3(0.0, 1.2, -0.58), Vector3(0.23, 0.25, 0.1), glow)
	for side in [-1.0, 1.0]:
		AlienBuilder.ellipsoid(root, Vector3(side * 0.72, 1.68, 0.0), Vector3(0.32, 0.2, 0.34), plate, Vector3(0.0, 0.0, side * -18.0))
		# ซี่โครงเกราะข้างอก
		for k in 3:
			AlienBuilder.ellipsoid(root, Vector3(side * 0.5, 1.4 - k * 0.2, -0.38),
				Vector3(0.05, 0.075, 0.2), plate, Vector3(0.0, side * 25.0, 0.0))

	# ผลึกพลังงานบนหลัง [ตำแหน่งฐาน, ทิศ, รัศมีฐาน, ความยาว]
	var spikes := [
		[Vector3(0.0, 1.7, 0.3), Vector3(0.0, 1.0, 0.35), 0.16, 0.9],
		[Vector3(-0.4, 1.6, 0.25), Vector3(-0.5, 1.0, 0.4), 0.12, 0.7],
		[Vector3(0.4, 1.6, 0.25), Vector3(0.5, 1.0, 0.4), 0.12, 0.7],
		[Vector3(-0.2, 1.55, 0.5), Vector3(-0.2, 0.8, 1.0), 0.1, 0.6],
		[Vector3(0.2, 1.55, 0.5), Vector3(0.2, 0.8, 1.0), 0.1, 0.6],
		[Vector3(-0.65, 1.5, 0.0), Vector3(-1.0, 1.0, 0.2), 0.1, 0.55],
		[Vector3(0.65, 1.5, 0.0), Vector3(1.0, 1.0, 0.2), 0.1, 0.55],
	]
	for s in spikes:
		var base: Vector3 = s[0]
		var dir: Vector3 = s[1]
		var r: float = s[2]
		var length: float = s[3]
		AlienBuilder.cone(root, base, dir, r, length, glow)

	# หัวเล็กจมในไหล่ + ตา 3 ดวง
	AlienBuilder.ellipsoid(root, Vector3(0.0, 1.85, -0.4), Vector3(0.28, 0.22, 0.3), shell)
	for x in [-0.12, 0.0, 0.12]:
		AlienBuilder.ellipsoid(root, Vector3(x, 1.88, -0.66), Vector3(0.04, 0.035, 0.04), glow)

	# ขาสั้นหนา
	var leg_ctrl_l := PackedVector3Array([
		Vector3(0.0, 0.0, 0.0), Vector3(-0.1, -0.3, -0.1),
		Vector3(-0.15, -0.6, 0.05), Vector3(-0.12, -0.92, 0.0)])
	var leg_ctrl_r := PackedVector3Array([
		Vector3(0.0, 0.0, 0.0), Vector3(0.1, -0.3, -0.1),
		Vector3(0.15, -0.6, 0.05), Vector3(0.12, -0.92, 0.0)])
	var leg_r := PackedFloat32Array([0.2, 0.17, 0.14, 0.12])
	for side in [-1.0, 1.0]:
		var hip := AlienBuilder.pivot(root, Vector3(side * 0.45, 0.95, 0.1))
		AlienBuilder.tube(hip, leg_ctrl_l if side < 0.0 else leg_ctrl_r, leg_r, shell, 6, 10,
			"aoe_leg_%d" % int(side))
		AlienBuilder.ellipsoid(hip, Vector3(side * 0.12, -0.9, -0.05), Vector3(0.2, 0.08, 0.28), plate)
		_legs.append(hip)

	# แขนใหญ่ลากยาว ปลายเป็นกำปั้น
	for side in [-1.0, 1.0]:
		var sh := AlienBuilder.pivot(root, Vector3(side * 0.85, 1.5, 0.0))
		var ctrl := PackedVector3Array([
			Vector3(0.0, 0.0, 0.0), Vector3(side * 0.2, -0.3, -0.1),
			Vector3(side * 0.2, -0.8, -0.25), Vector3(side * 0.15, -1.2, -0.15)])
		AlienBuilder.tube(sh, ctrl, PackedFloat32Array([0.2, 0.19, 0.18, 0.2]), shell, 6, 10,
			"aoe_arm_%d" % int(side))
		AlienBuilder.ellipsoid(sh, Vector3(side * 0.15, -1.25, -0.15), Vector3(0.27, 0.25, 0.27), plate)
		AlienBuilder.ellipsoid(sh, Vector3(side * 0.15, -1.3, -0.4), Vector3(0.07, 0.07, 0.05), glow)
		_arms.append(sh)

func _animate(delta: float) -> void:
	var swing := sin(_walk_phase) * 0.45 * _move_amt
	_legs[0].rotation.x = swing
	_legs[1].rotation.x = -swing

	# ท่าร่าย: ยกสองแขนขึ้นเหนือหัวช้าๆ ตามวงแดงที่เต็มขึ้น แล้วทุบลงตอนระเบิด
	_pose = lerpf(_pose, _tele, clampf(14.0 * delta, 0.0, 1.0))
	for i in _arms.size():
		var sgn := 1.0 if i == 0 else -1.0
		var idle := sgn * sin(_walk_phase) * 0.25 * _move_amt + sin(_t * 1.2 + float(i)) * 0.03
		_arms[i].rotation.x = lerpf(idle, 2.6, _pose)

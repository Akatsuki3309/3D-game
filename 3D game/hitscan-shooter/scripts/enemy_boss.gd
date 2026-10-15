class_name EnemyBoss
extends EnemyBase

# บอส "จอมทัพเอเลี่ยน": ตัวใหญ่ หางยาว เขาโค้ง ผลึกบนหลัง
# WaveManager สร้างให้ตอน Wave ที่ลงตัวด้วย boss_every (5 / 10 / 15 ...) ไม่ต้องมี scene
# - 3 ท่าโจมตี สุ่มสลับกัน (ไม่ซ้ำท่าเดิมติดกัน) เลือกตามระยะห่างจากผู้เล่น
#     VOLLEY : ยิงกระสุนพลาสม่าเป็นพัด (หลบด้วยการเคลื่อนที่)
#     SLAM   : ทุบพื้นเป็นวงกว้างรอบตัว (กระโดดข้ามคลื่น หรือวิ่งออกนอกวงก่อนทัน)
#     CHARGE : ง้างแล้วพุ่งชนเป็นเส้นตรง (เบี่ยงข้าง) พุ่งเสร็จจะเหนื่อยเปิดช่องให้ยิง
# - HP เหลือ enrage_ratio (50%) = คลั่ง: เร็วขึ้น คูลดาวน์สั้นลง กระสุนเยอะขึ้น ยิงสองชุด
# - อยู่ใน group "boss" (Wave HUD ใช้วาดแถบเลือดบอส)

enum Atk { NONE, VOLLEY, SLAM, CHARGE }

@export_group("Boss")
@export var volley_count := 5
@export var volley_spread_deg := 14.0
@export var projectile_speed := 18.0
@export var slam_radius := 9.0
@export var charge_speed := 22.0
@export var charge_time := 0.7
@export var attack_cooldown := 2.2
@export var enrage_ratio := 0.5
@export var keep_range := 11.0        # เดินเข้าหาจนถึงระยะนี้แล้วหยุดยืนรอโจมตี

var hp_max := 1.0
var enraged := false

var _atk := Atk.NONE
var _last_atk := Atk.NONE
var _cd := 2.0
var _recover := 0.0
var _charge_dir := Vector3.ZERO
var _charge_left := 0.0
var _charge_hit := false
var _raise := 2.6          # องศาที่แขนยกในท่าง้างของท่านั้น (เรเดียน)

var _marker: Node3D
var _inner_mat: StandardMaterial3D

var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _tail: Node3D
var _pose := 0.0

func _init() -> void:
	body_color = Color(0.75, 0.15, 0.35)
	glow_color = Color(1.0, 0.55, 0.1)
	body_height = 3.6
	body_radius = 1.2
	max_hp = 1500.0
	move_speed = 4.0
	damage = 25.0

func _setup() -> void:
	hp_max = hp
	add_to_group("boss")
	_cd = 2.0

# ---------------------------------------------------------------
# พฤติกรรม
# ---------------------------------------------------------------
func _think(delta: float) -> void:
	_cd -= delta

	var to := _flat_to_target()
	var dist := to.length()
	var dir := to.normalized()

	# เหนื่อยหลังโจมตี: ยืนนิ่ง เป็นช่องให้ผู้เล่นยิง
	if _recover > 0.0:
		_recover -= delta
		_move_dir(Vector3.ZERO, 0.0, delta)
		return

	# กำลังพุ่งชน
	if _atk == Atk.CHARGE and _charge_left > 0.0:
		_charge_left -= delta
		velocity.x = _charge_dir.x * charge_speed
		velocity.z = _charge_dir.z * charge_speed
		_face(_charge_dir, delta)
		if not _charge_hit and dist < body_radius + 1.4:
			_charge_hit = true
			target.take_damage(attack_damage * 1.2)
			if "velocity" in target:
				target.velocity = Vector3(_charge_dir.x * 14.0, 5.0, _charge_dir.z * 14.0)
		if _charge_left <= 0.0:
			_charge_left = 0.0
			_finish_attack(0.9)
		return

	# กำลังง้างท่า: ยืนนิ่ง (ท่าพัดกับพุ่งหันตามผู้เล่น ท่าทุบหันค้างไว้)
	if _atk != Atk.NONE:
		_move_dir(Vector3.ZERO, 0.0, delta)
		if _atk != Atk.SLAM:
			_face(dir, delta)
		return

	_face(dir, delta)
	if dist > keep_range:
		_move_dir(dir, speed, delta)
	else:
		_move_dir(Vector3.ZERO, 0.0, delta)

	if _cd <= 0.0:
		_choose_attack(dist)

func _choose_attack(dist: float) -> void:
	var options: Array = []
	if dist > 16.0:
		options = [Atk.VOLLEY, Atk.CHARGE, Atk.VOLLEY]
	elif dist < 7.0:
		options = [Atk.SLAM, Atk.SLAM, Atk.CHARGE]
	else:
		options = [Atk.VOLLEY, Atk.SLAM, Atk.CHARGE]

	var pool := options.filter(func(a): return a != _last_atk)
	if pool.is_empty():
		pool = options
	var pick: int = pool.pick_random()

	match pick:
		Atk.VOLLEY: _volley()
		Atk.SLAM: _slam()
		Atk.CHARGE: _charge()

func _finish_attack(recover: float) -> void:
	_last_atk = _atk
	_atk = Atk.NONE
	_cd = attack_cooldown * (0.65 if enraged else 1.0)
	_recover = recover * (0.7 if enraged else 1.0)

# ---------------------------------------------------------------
# ท่า 1: ยิงกระสุนเป็นพัด
# ---------------------------------------------------------------
func _volley() -> void:
	_atk = Atk.VOLLEY
	_raise = 1.2
	var wind := 0.55 if enraged else 0.8
	_telegraph(Color(1.0, 0.9, 0.2), wind)

	await get_tree().create_timer(wind, false).timeout
	if _dead or not is_inside_tree():
		return

	var rounds := 2 if enraged else 1
	for r in rounds:
		_fire_fan()
		if r < rounds - 1:
			await get_tree().create_timer(0.35, false).timeout
			if _dead or not is_inside_tree():
				return
	_finish_attack(0.5)

func _fire_fan() -> void:
	if not _target_alive():
		return
	var origin := global_position + Vector3(0.0, body_height * 0.62, 0.0)
	var base_dir := (target.global_position - origin).normalized()
	var count := volley_count + (2 if enraged else 0)
	for i in count:
		var off := (float(i) - float(count - 1) * 0.5) * deg_to_rad(volley_spread_deg)
		var p := EnemyProjectile.new()
		get_tree().current_scene.add_child(p)
		p.global_position = origin
		p.setup(self, base_dir.rotated(Vector3.UP, off) * projectile_speed, attack_damage * 0.6)

# ---------------------------------------------------------------
# ท่า 2: ทุบพื้นเป็นวง (กระโดดข้ามได้)
# ---------------------------------------------------------------
func _slam() -> void:
	_atk = Atk.SLAM
	_raise = 2.7
	var wind := 0.8 if enraged else 1.1
	_telegraph(Color(1.0, 0.2, 0.1), wind)
	_spawn_marker(wind)

	await get_tree().create_timer(wind, false).timeout
	if _dead or not is_inside_tree():
		return

	if _target_alive():
		var d := target.global_position - global_position
		var airborne: bool = d.y > 1.6   # ผู้เล่นอยู่กลางอากาศ = ข้ามคลื่นได้
		d.y = 0.0
		if d.length() <= slam_radius and not airborne:
			target.take_damage(attack_damage * 1.5)

	if is_instance_valid(_marker):
		_inner_mat.albedo_color = Color(1.0, 0.9, 0.6, 0.9)
		var tw := _marker.create_tween()
		tw.tween_property(_marker, "scale", Vector3(1.15, 1.0, 1.15), 0.2)
		tw.tween_callback(_marker.queue_free)
	_finish_attack(0.9)

func _spawn_marker(duration: float) -> void:
	_marker = Node3D.new()
	_marker.top_level = true   # อยู่ในพิกัดโลก ไม่ตามตัวบอส แต่ถูกลบพร้อมบอส
	add_child(_marker)
	_marker.global_position = Vector3(global_position.x, global_position.y + 0.04, global_position.z)

	var outer := _make_disc(Color(1.0, 0.1, 0.1, 0.22))
	_marker.add_child(outer.mesh_instance)

	var inner := _make_disc(Color(1.0, 0.15, 0.1, 0.45))
	inner.mesh_instance.position.y = 0.02
	inner.mesh_instance.scale = Vector3(0.02, 1.0, 0.02)
	_marker.add_child(inner.mesh_instance)
	_inner_mat = inner.material

	var tw: Tween = inner.mesh_instance.create_tween()
	tw.tween_property(inner.mesh_instance, "scale", Vector3.ONE, duration)

func _make_disc(color: Color) -> Dictionary:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var mesh := CylinderMesh.new()
	mesh.top_radius = slam_radius
	mesh.bottom_radius = slam_radius
	mesh.height = 0.04
	mesh.material = mat

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return {"mesh_instance": mi, "material": mat}

# ---------------------------------------------------------------
# ท่า 3: พุ่งชน
# ---------------------------------------------------------------
func _charge() -> void:
	_atk = Atk.CHARGE
	_raise = -0.5
	var wind := 0.5 if enraged else 0.7
	_telegraph(Color(1.0, 0.5, 0.1), wind)

	await get_tree().create_timer(wind, false).timeout
	if _dead or not is_inside_tree():
		return
	if not _target_alive():
		_finish_attack(0.3)
		return

	_charge_dir = _flat_to_target().normalized()
	_charge_hit = false
	_charge_left = charge_time

# ---------------------------------------------------------------
# เฟสคลั่ง
# ---------------------------------------------------------------
func take_damage(amount: float) -> void:
	super(amount)
	if not _dead and not enraged and hp <= hp_max * enrage_ratio:
		_enrage()

func _enrage() -> void:
	enraged = true
	glow_color = Color(1.0, 0.12, 0.08)
	speed *= 1.3
	_cd = minf(_cd, 0.8)
	_strike = 1.0
	var tw := create_tween()
	tw.tween_property(_model, "scale", Vector3.ONE * 1.12, 0.25)
	tw.tween_property(_model, "scale", Vector3.ONE, 0.3)

func _on_death() -> void:
	if is_instance_valid(_marker):
		_marker.queue_free()

# ---------------------------------------------------------------
# โมเดล (หน้า = -Z, เท้าอยู่ y = 0)
# ---------------------------------------------------------------
func _build_visual(root: Node3D) -> void:
	var shell := _mat
	var plate := _plate
	var glow := _glow

	# ลำตัว สะโพก โหนกหลัง
	AlienBuilder.ellipsoid(root, Vector3(0.0, 2.2, 0.1), Vector3(0.95, 0.9, 1.15), shell, Vector3(-12.0, 0.0, 0.0))
	AlienBuilder.ellipsoid(root, Vector3(0.0, 1.7, 0.2), Vector3(0.75, 0.4, 0.7), plate)
	AlienBuilder.ellipsoid(root, Vector3(0.0, 2.8, 0.55), Vector3(0.7, 0.6, 0.8), plate)

	# แกนพลังงานกลางอก + ซี่โครงเกราะ
	AlienBuilder.ellipsoid(root, Vector3(0.0, 2.2, -1.0), Vector3(0.38, 0.42, 0.15), glow)
	for side in [-1.0, 1.0]:
		for k in 4:
			AlienBuilder.ellipsoid(root, Vector3(side * 0.8, 2.6 - k * 0.28, -0.55),
				Vector3(0.07, 0.1, 0.35), plate, Vector3(0.0, side * 25.0, 0.0))

	# ผลึกบนหลัง [ฐาน, ทิศ, รัศมีฐาน, ความยาว]
	var spikes := [
		[Vector3(0.0, 3.2, 0.5), Vector3(0.0, 1.0, 0.35), 0.28, 1.5],
		[Vector3(-0.6, 3.0, 0.4), Vector3(-0.5, 1.0, 0.4), 0.2, 1.1],
		[Vector3(0.6, 3.0, 0.4), Vector3(0.5, 1.0, 0.4), 0.2, 1.1],
		[Vector3(-0.35, 2.9, 0.9), Vector3(-0.2, 0.8, 1.0), 0.17, 0.95],
		[Vector3(0.35, 2.9, 0.9), Vector3(0.2, 0.8, 1.0), 0.17, 0.95],
		[Vector3(-1.0, 2.7, 0.0), Vector3(-1.0, 1.0, 0.2), 0.16, 0.8],
		[Vector3(1.0, 2.7, 0.0), Vector3(1.0, 1.0, 0.2), 0.16, 0.8],
	]
	for s in spikes:
		var base: Vector3 = s[0]
		var dir: Vector3 = s[1]
		var r: float = s[2]
		var length: float = s[3]
		AlienBuilder.cone(root, base, dir, r, length, glow)

	# คอ + หัว + ตา 4 ดวง
	AlienBuilder.tube(root,
		PackedVector3Array([Vector3(0.0, 2.6, -0.7), Vector3(0.0, 2.85, -1.0)]),
		PackedFloat32Array([0.35, 0.3]), shell, 4, 12, "boss_neck")
	AlienBuilder.ellipsoid(root, Vector3(0.0, 2.95, -1.3), Vector3(0.42, 0.38, 0.62), shell, Vector3(10.0, 0.0, 0.0))
	for x in [-0.22, -0.08, 0.08, 0.22]:
		AlienBuilder.ellipsoid(root, Vector3(x, 3.0, -1.82), Vector3(0.06, 0.05, 0.07), glow)

	# เขาโค้ง + ขากรรไกร
	for side in [-1.0, 1.0]:
		var horn := PackedVector3Array([
			Vector3(side * 0.22, 3.2, -1.1), Vector3(side * 0.55, 3.55, -1.0),
			Vector3(side * 0.75, 3.95, -1.2), Vector3(side * 0.7, 4.2, -1.6)])
		AlienBuilder.tube(root, horn, PackedFloat32Array([0.1, 0.08, 0.05, 0.005]), plate, 6, 8,
			"boss_horn_%d" % int(side))
		var horn2 := PackedVector3Array([
			Vector3(side * 0.12, 3.3, -0.9), Vector3(side * 0.25, 3.75, -0.8),
			Vector3(side * 0.2, 4.15, -0.9)])
		AlienBuilder.tube(root, horn2, PackedFloat32Array([0.07, 0.05, 0.004]), plate, 6, 8,
			"boss_horn2_%d" % int(side))
		var jaw := PackedVector3Array([
			Vector3(side * 0.15, 2.7, -1.8), Vector3(side * 0.35, 2.5, -2.1),
			Vector3(side * 0.15, 2.35, -2.4)])
		AlienBuilder.tube(root, jaw, PackedFloat32Array([0.07, 0.05, 0.008]), plate, 6, 8,
			"boss_jaw_%d" % int(side))

	# ขาหนา
	var leg_ctrl := PackedVector3Array([
		Vector3(0.0, 0.0, 0.0), Vector3(0.0, -0.5, -0.4),
		Vector3(0.0, -1.1, 0.2), Vector3(0.0, -1.72, -0.15)])
	var leg_r := PackedFloat32Array([0.3, 0.24, 0.16, 0.09])
	for side in [-1.0, 1.0]:
		var hip := AlienBuilder.pivot(root, Vector3(side * 0.55, 1.75, 0.2))
		AlienBuilder.tube(hip, leg_ctrl, leg_r, shell, 6, 10, "boss_leg")
		AlienBuilder.ellipsoid(hip, Vector3(0.0, -1.7, -0.3), Vector3(0.16, 0.07, 0.3), plate)
		_legs.append(hip)

	# แขนเคียวยักษ์ (ซ้าย / ขวา)
	for side in [-1.0, 1.0]:
		var sh := AlienBuilder.pivot(root, Vector3(side * 1.15, 2.6, -0.1))
		AlienBuilder.ellipsoid(sh, Vector3(0.0, 0.1, 0.0), Vector3(0.4, 0.3, 0.45), plate)
		var ctrl := PackedVector3Array([
			Vector3(0.0, 0.0, 0.0), Vector3(side * 0.2, -0.24, -0.6),
			Vector3(side * 0.36, -0.2, -1.24), Vector3(side * 0.28, 0.0, -1.9),
			Vector3(0.0, 0.12, -2.4)])
		AlienBuilder.tube(sh, ctrl, PackedFloat32Array([0.22, 0.18, 0.15, 0.09, 0.008]), plate, 6, 10,
			"boss_arm_%d" % int(side))
		AlienBuilder.ellipsoid(sh, Vector3(side * 0.2, -0.24, -0.6), Vector3(0.22, 0.2, 0.22), shell)
		AlienBuilder.ellipsoid(sh, Vector3(0.0, 0.12, -2.36), Vector3(0.03, 0.03, 0.06), glow)
		_arms.append(sh)

	# หางยาว
	_tail = AlienBuilder.pivot(root, Vector3(0.0, 1.9, 0.8))
	AlienBuilder.tube(_tail,
		PackedVector3Array([Vector3(0.0, 0.0, 0.0), Vector3(0.0, -0.2, 0.9),
			Vector3(0.0, -0.1, 1.9), Vector3(0.0, 0.5, 2.7)]),
		PackedFloat32Array([0.3, 0.22, 0.14, 0.005]), shell, 6, 10, "boss_tail")
	AlienBuilder.ellipsoid(_tail, Vector3(0.0, 0.48, 2.55), Vector3(0.07, 0.07, 0.18), glow)

func _animate(delta: float) -> void:
	var swing := sin(_walk_phase) * 0.5 * _move_amt
	_legs[0].rotation.x = swing
	_legs[1].rotation.x = -swing

	# ท่าง้าง: แขนยกตามท่าที่กำลังใช้ (_raise) แล้วสะบัดลงตอนปล่อยท่า
	_pose = lerpf(_pose, _tele, clampf(12.0 * delta, 0.0, 1.0))
	for i in _arms.size():
		var sgn := 1.0 if i == 0 else -1.0
		var idle := sgn * sin(_walk_phase) * 0.2 * _move_amt + 0.05 + sin(_t * 1.3 + float(i)) * 0.03
		_arms[i].rotation.x = lerpf(idle, _raise, _pose) - _strike * 1.4

	_tail.rotation.y = sin(_t * 1.6) * 0.3 + sin(_walk_phase) * 0.15 * _move_amt
	_tail.rotation.x = _pose * 0.4

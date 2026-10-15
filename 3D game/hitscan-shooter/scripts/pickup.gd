extends Node3D

# ไอเทมเก็บบนพื้น (เลือด / กระสุน) สร้างโมเดลชั่วคราวจากโค้ดล้วน ไม่ต้องมี mesh
# - เดินเข้าใกล้ = ดูดเข้าหาตัว แล้วเก็บเอง (ถ้าเต็มอยู่จะไม่เก็บ ไอเทมค้างไว้ก่อน)
# - เล็งครอสแฮร์ไปที่ไอเทม = ขึ้นป้ายชื่อเหนือไอเทม (ทำโดย pickup_hover.gd ซึ่งถูกสร้างให้เองอัตโนมัติ)
# - ไอเทมหายเองเมื่อครบ lifetime (กะพริบเตือน 5 วินาทีสุดท้าย)
#
# วางเองใน editor ได้: เพิ่ม Node3D → ผูกสคริปต์นี้ → เลือก Kind ใน Inspector

signal collected(kind: int, amount: float)

enum Kind { HEALTH, AMMO }

const HoverScript := preload("res://scripts/pickup_hover.gd")
const HOVER_HEIGHT := 0.75     # ตัวไอเทมลอยสูงจากพื้นเท่าไร
const BLINK_TIME := 5.0

@export var kind: Kind = Kind.HEALTH
@export var amount := 0.0              # 0 = ค่าเริ่มต้นตามชนิด (เลือด 25 / กระสุน 7)
@export var lifetime := 30.0           # วินาที, 0 = ไม่หาย
@export var collect_radius := 1.5      # ระยะเก็บ (แนวราบ)
@export var magnet_range := 4.0        # ระยะเริ่มดูดเข้าหาผู้เล่น
@export var hover_radius := 0.8        # ขนาดพื้นที่ให้ครอสแฮร์ชี้โดน (เมตร)

var _visual: Node3D
var _player            # ไม่ระบุชนิด เพราะอ่าน health / camera ของ player.gd
var _age := 0.0
var _time := 0.0
var _phase := randf() * TAU
var _magnet_speed := 6.0
var _done := false

func _ready() -> void:
	add_to_group("pickup")
	_build_visual()
	_ensure_hover.call_deferred()

	# เด้งโผล่ตอนเกิด
	_visual.scale = Vector3.ZERO
	var tw := create_tween()
	tw.tween_property(_visual, "scale", Vector3.ONE, 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _process(delta: float) -> void:
	if _done:
		return
	_age += delta
	_time += delta

	# ลอยขึ้นลง + หมุน
	_visual.position.y = HOVER_HEIGHT + sin(_time * 2.4 + _phase) * 0.12
	_visual.rotation.y += delta * 1.6

	# อายุ
	if lifetime > 0.0:
		if _age >= lifetime:
			_vanish()
			return
		if _age > lifetime - BLINK_TIME:
			_visual.visible = int(_age * 8.0) % 2 == 0

	var p = _get_player()
	if p == null or p.is_dead:
		return

	var flat := Vector3(p.global_position.x - global_position.x, 0.0, p.global_position.z - global_position.z)
	var dist := flat.length()
	var dy: float = p.global_position.y - global_position.y

	if not can_collect():
		_magnet_speed = 6.0
		return

	if dist <= collect_radius and dy > -1.0 and dy < 2.6:
		if _apply(p):
			collected.emit(kind, _amount())
			_vanish()
	elif dist <= magnet_range:
		_magnet_speed = minf(_magnet_speed + 30.0 * delta, 22.0)
		global_position += flat.normalized() * minf(_magnet_speed * delta, dist)
	else:
		_magnet_speed = 6.0

# ---------------------------------------------------------------
# ข้อมูลให้ป้าย Title (pickup_hover.gd เรียก)
# ---------------------------------------------------------------
func title_text() -> String:
	return GameSettings.t("pickup.health") if kind == Kind.HEALTH else GameSettings.t("pickup.ammo")

func desc_text() -> String:
	if kind == Kind.HEALTH:
		return GameSettings.t("pickup.hp_plus") % int(_amount())
	return GameSettings.t("pickup.ammo_plus") % int(_amount())

# คืนข้อความเมื่อเก็บไม่ได้ (ว่าง = เก็บได้ปกติ)
func status_text() -> String:
	if can_collect():
		return ""
	return GameSettings.t("pickup.hp_full") if kind == Kind.HEALTH else GameSettings.t("pickup.ammo_full")

func accent_color() -> Color:
	return Color(1.0, 0.3, 0.35) if kind == Kind.HEALTH else Color(1.0, 0.8, 0.25)

func hover_center() -> Vector3:
	return _visual.global_position if _visual != null else global_position

func can_collect() -> bool:
	var p = _get_player()
	if p == null:
		return false
	if kind == Kind.HEALTH:
		return p.health < p.max_health
	var gun = p.camera
	return gun != null and gun.reserve < gun.max_reserve

# ---------------------------------------------------------------
# ภายใน
# ---------------------------------------------------------------
func _amount() -> float:
	if amount > 0.0:
		return amount
	return 25.0 if kind == Kind.HEALTH else 7.0

func _apply(p) -> bool:
	if kind == Kind.HEALTH:
		var before: float = p.health
		p.heal(_amount())
		return p.health > before
	var accepted: int = p.camera.add_ammo(int(_amount()))
	return accepted > 0

func _vanish() -> void:
	_done = true
	remove_from_group("pickup")
	_visual.visible = true
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_visual, "scale", Vector3.ZERO, 0.15)
	tw.tween_property(_visual, "position:y", HOVER_HEIGHT + 0.8, 0.15)
	tw.chain().tween_callback(queue_free)

func _get_player():
	if is_instance_valid(_player):
		return _player
	_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		var scene := get_tree().current_scene
		if scene != null:
			_player = scene.find_child("Player", true, false)
	return _player

# สร้างตัวจัดการป้ายชื่อ 1 ตัวต่อฉาก (ถ้ายังไม่มี)
func _ensure_hover() -> void:
	var scene := get_tree().current_scene
	if scene == null or scene.has_node("PickupHover"):
		return
	var h := Node.new()
	h.set_script(HoverScript)
	h.name = "PickupHover"
	scene.add_child(h)

# ---------------------------------------------------------------
# โมเดลชั่วคราว
# ---------------------------------------------------------------
func _build_visual() -> void:
	var col := accent_color()

	_visual = Node3D.new()
	_visual.position.y = HOVER_HEIGHT
	add_child(_visual)

	if kind == Kind.HEALTH:
		# กล่องแดง + กากบาทขาวรอบด้าน
		_visual.add_child(_box(Vector3(0.5, 0.5, 0.5), Vector3.ZERO, col))
		for i in 2:
			var holder := Node3D.new()
			holder.rotation.y = PI * 0.5 * i
			holder.add_child(_box(Vector3(0.34, 0.1, 0.54), Vector3.ZERO, Color.WHITE))
			holder.add_child(_box(Vector3(0.1, 0.34, 0.54), Vector3.ZERO, Color.WHITE))
			_visual.add_child(holder)
	else:
		# กล่องกระสุนสีทอง + หัวกระสุน 3 อันโผล่ด้านบน
		_visual.add_child(_box(Vector3(0.56, 0.32, 0.36), Vector3(0, -0.08, 0), col))
		_visual.add_child(_box(Vector3(0.58, 0.07, 0.38), Vector3(0, -0.08, 0), Color(0.35, 0.25, 0.05)))
		for x in [-0.16, 0.0, 0.16]:
			_visual.add_child(_bullet(Vector3(x, 0.2, 0.0)))

	# วงเรืองบนพื้น + แสงลำเล็กๆ ให้เห็นไอเทมจากไกล
	var ring := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.75
	rm.bottom_radius = 0.75
	rm.height = 0.02
	ring.mesh = rm
	ring.material_override = _glow_mat(Color(col, 0.45))
	ring.position.y = 0.03
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)

	var beam := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.05
	bm.bottom_radius = 0.05
	bm.height = 5.0
	beam.mesh = bm
	beam.material_override = _glow_mat(Color(col, 0.22))
	beam.position.y = 2.5
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)

	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 1.2
	light.omni_range = 4.0
	light.position.y = 1.0
	add_child(light)

func _box(size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = _solid_mat(color)
	return mi

func _bullet(pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.045
	cm.bottom_radius = 0.055
	cm.height = 0.26
	mi.mesh = cm
	mi.position = pos
	mi.material_override = _solid_mat(Color(0.85, 0.6, 0.2))
	return mi

func _solid_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 0.5
	return m

func _glow_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

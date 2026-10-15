class_name MapBuilder
extends Node

# ตัวสร้างแมพธีม "Fallen Earth" (โลกล่มสลาย) จากโค้ดล้วน ไม่ต้องมีโมเดล/รูป ไม่ต้องแก้ฉาก
# WaveManager สร้างให้เองตอนเริ่มเกม สิ่งที่ทำ:
#   - ทาสีพื้น (CSGBox3D) ให้เป็นดินฝุ่นมีลาย
#   - ท้องฟ้าฝุ่นสีส้ม + หมอก + แสงอาทิตย์อุ่น + glow (แก้ที่ WorldEnvironment/DirectionalLight3D เดิมในฉาก)
#   - วางซากตึก / รถพัง / เสาหัก / ต้นไม้ตาย / ก้อนหิน / ถังน้ำมัน / ถังไฟ / หลุมระเบิด / เศษหิน
#   - เส้นขอบฟ้าซากเมืองไกลๆ (ไม่มี collision) + ฝุ่นลอยรอบตัวผู้เล่น
# - สิ่งของส่วนใหญ่มี collision = ใช้เป็นที่กำบังได้ (กระสุนมอนตีไกลและกระสุนผู้เล่นชนมัน)
# - ใช้ seed คงที่ แมพจึงหน้าตาเดิมทุกรอบ (เปลี่ยน map_seed เพื่อได้แมพใหม่)
# - is_free() ไว้ให้ WaveManager เช็คไม่ให้มอนเกิดทับสิ่งกีดขวาง

@export var map_seed := 20261008
@export var clear_radius := 16.0        # รอบจุดเริ่มต้นผู้เล่นปล่อยโล่ง
@export var decor_radius := 210.0       # วางของไกลสุดจากกลางแมพเท่านี้

@export_group("Counts")
@export var ruin_count := 14
@export var car_count := 12
@export var pillar_count := 22
@export var tree_count := 45
@export var rock_count := 90
@export var barrel_cluster_count := 10
@export var fire_barrel_count := 6
@export var crater_count := 20
@export var rubble_count := 700
@export var skyline_count := 70

@export_group("Atmosphere")
@export var fog_density := 0.0035       # มาก = หมอกหนา (ปืนยิงไกล 500 ม. อย่าตั้งเกิน 0.006)
@export var sun_energy := 1.0
@export var dust_particles := true

var _rng := RandomNumberGenerator.new()
var _decor: Node3D
var _blocked: Array[Vector3] = []       # (x, z, รัศมี) ของสิ่งกีดขวางที่มี collision
var _noise_tex: NoiseTexture2D
var _mats := {}

func _ready() -> void:
	# รอให้ฉากหลักตั้งค่าเสร็จก่อน (ห้าม add_child ให้ฉากระหว่างมัน _ready อยู่)
	build.call_deferred()

# ---------------------------------------------------------------
# เรียกจากภายนอก
# ---------------------------------------------------------------
# true = จุดนี้ไม่ทับสิ่งกีดขวาง (margin = เผื่อขนาดตัวมอน)
func is_free(pos: Vector3, margin := 1.2) -> bool:
	for b in _blocked:
		if Vector2(b.x, b.y).distance_to(Vector2(pos.x, pos.z)) < b.z + margin:
			return false
	return true

# ---------------------------------------------------------------
# สร้างแมพ
# ---------------------------------------------------------------
# กันพื้นที่วงกลม (เช่น ที่จอดกระสวยในคัทซีน) ไม่ให้วางของตกแต่ง และไม่ให้มอนเกิดทับ
# ต้องเรียกก่อน build() ทำงาน (build ถูกเรียกแบบ deferred จึงเรียกใน _ready ของ WaveManager ได้)
func reserve(center: Vector2, radius: float) -> void:
	_blocked.append(Vector3(center.x, center.y, radius))

func build() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return

	_rng.seed = map_seed
	_make_noise()

	_decor = Node3D.new()
	_decor.name = "Decor"
	scene.add_child(_decor)

	_style_floor(scene)
	_style_environment(scene)
	_style_sun(scene)

	# ของใหญ่วางก่อน ของเล็กค่อยเลี่ยงตามหลัง
	_place_ruins()
	_place_cars()
	_place_pillars()
	_place_barrels()
	_place_fire_barrels()
	_place_rocks()
	_place_trees()

	_place_craters()
	_place_rubble()
	_build_skyline()
	if dust_particles:
		_spawn_dust(scene)

# ---------------------------------------------------------------
# พื้น / ท้องฟ้า / แสง
# ---------------------------------------------------------------
func _make_noise() -> void:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.012
	n.fractal_octaves = 4
	n.seed = map_seed

	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(0.5, 0.5, 0.5), Color(0.78, 0.78, 0.78), Color(1, 1, 1)])

	_noise_tex = NoiseTexture2D.new()
	_noise_tex.noise = n
	_noise_tex.seamless = true
	_noise_tex.width = 512
	_noise_tex.height = 512
	_noise_tex.color_ramp = g

# วัสดุสีเดียว + ลายนอยส์ (ขนาดลายคงที่ตามโลก ไม่ยืดตามขนาดวัตถุ)
func _mat(color: Color, tex_scale := 0.25) -> StandardMaterial3D:
	var key := "%s_%s" % [color, tex_scale]
	if _mats.has(key):
		return _mats[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.albedo_texture = _noise_tex
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * tex_scale
	m.roughness = 1.0
	_mats[key] = m
	return m

func _style_floor(scene: Node) -> void:
	var f = scene.find_child("CSGBox3D", true, false)
	if f is CSGBox3D:
		f.material = _mat(Color(0.30, 0.235, 0.18), 0.06)

func _style_environment(scene: Node) -> void:
	var we: WorldEnvironment = null
	var found := scene.find_children("*", "WorldEnvironment", true, false)
	if found.size() > 0:
		we = found[0]
	else:
		we = WorldEnvironment.new()
		we.name = "WorldEnvironment"
		scene.add_child(we)
	if we.environment == null:
		we.environment = Environment.new()
	var env := we.environment

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.16, 0.18, 0.24)
	sky_mat.sky_horizon_color = Color(0.72, 0.46, 0.32)
	sky_mat.sky_curve = 0.18
	sky_mat.ground_horizon_color = Color(0.72, 0.46, 0.32)
	sky_mat.ground_bottom_color = Color(0.18, 0.13, 0.11)
	sky_mat.ground_curve = 0.05
	sky_mat.sun_angle_max = 25.0
	sky_mat.sun_curve = 0.15
	var sky := Sky.new()
	sky.sky_material = sky_mat

	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	env.fog_enabled = true
	env.fog_light_color = Color(0.58, 0.40, 0.30)
	env.fog_density = fog_density
	env.fog_sky_affect = 0.35
	env.fog_aerial_perspective = 0.4

	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.04

func _style_sun(scene: Node) -> void:
	var l = scene.find_child("DirectionalLight3D", true, false)
	if l is DirectionalLight3D:
		l.light_color = Color(1.0, 0.78, 0.58)
		l.light_energy = sun_energy
		l.shadow_enabled = true
		l.directional_shadow_max_distance = 140.0

# ---------------------------------------------------------------
# ตัวช่วยวางของ
# ---------------------------------------------------------------
# หาจุดว่างสำหรับของที่มี collision (คืน Vector2 หรือ null ถ้าหาไม่ได้) และจองพื้นที่ไว้ให้เลย
func _find_spot(radius: float, min_r := -1.0, max_r := -1.0) -> Variant:
	var lo := clear_radius + radius
	if min_r >= 0.0:
		lo = min_r
	var hi := decor_radius
	if max_r >= 0.0:
		hi = max_r
	for i in 14:
		var a := _rng.randf() * TAU
		var d := sqrt(_rng.randf_range(lo * lo, hi * hi))   # สุ่มให้กระจายสม่ำเสมอทั้งพื้นที่
		var p := Vector2(cos(a), sin(a)) * d
		if _is_clear(p, radius):
			_blocked.append(Vector3(p.x, p.y, radius))
			return p
	return null

func _is_clear(p: Vector2, radius: float) -> bool:
	for b in _blocked:
		if Vector2(b.x, b.y).distance_to(p) < b.z + radius + 1.5:
			return false
	return true

func _new_body(p: Vector2, yaw := 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = Vector3(p.x, 0.0, p.y)
	body.rotation.y = yaw
	_decor.add_child(body)
	return body

# กล่อง (มีรูปทรง + จะมี collision ด้วยหรือไม่ก็ได้)
func _add_box(parent: Node3D, size: Vector3, pos: Vector3, yaw: float, mat: Material, collide := true) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = yaw
	parent.add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.position = pos
		cs.rotation.y = yaw
		parent.add_child(cs)

func _add_cyl(parent: Node3D, r_top: float, r_bottom: float, h: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bottom
	cm.height = h
	cm.radial_segments = 10
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

func _add_cyl_collision(parent: Node3D, radius: float, h: float, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var s := CylinderShape3D.new()
	s.radius = radius
	s.height = h
	cs.shape = s
	cs.position = pos
	parent.add_child(cs)

func _add_box_collision(parent: Node3D, size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = size
	cs.shape = s
	cs.position = pos
	parent.add_child(cs)

# ---------------------------------------------------------------
# ซากตึก: กำแพงแหว่งๆ เป็นรูปตัว U (เปิดด้านหนึ่ง) ใช้เป็นที่กำบัง
# ---------------------------------------------------------------
func _place_ruins() -> void:
	for i in ruin_count:
		var spot = _find_spot(8.0)
		if spot == null:
			continue
		var p: Vector2 = spot
		var body := _new_body(p, _rng.randf() * TAU)
		var w := _rng.randf_range(7.0, 11.0)
		var d := _rng.randf_range(6.0, 9.0)
		var mat := _mat(Color(0.34, 0.32, 0.30), 0.18)

		_wall(body, Vector3(0.0, 0.0, -d * 0.5), w, 0.0, mat)            # ด้านหลัง
		if _rng.randf() < 0.85:
			_wall(body, Vector3(-w * 0.5, 0.0, 0.0), d, PI * 0.5, mat)   # ด้านซ้าย
		if _rng.randf() < 0.85:
			_wall(body, Vector3(w * 0.5, 0.0, 0.0), d, PI * 0.5, mat)    # ด้านขวา

		# เศษปูนในซาก (ไม่มี collision)
		var rub := _mat(Color(0.30, 0.28, 0.26), 0.3)
		for j in _rng.randi_range(4, 8):
			var s := Vector3(_rng.randf_range(0.4, 1.4), _rng.randf_range(0.25, 0.8), _rng.randf_range(0.4, 1.4))
			var pos := Vector3(_rng.randf_range(-w * 0.4, w * 0.4), s.y * 0.4, _rng.randf_range(-d * 0.4, d * 0.4))
			_add_box(body, s, pos, _rng.randf() * TAU, rub, false)

# กำแพงยาวแบ่งเป็นท่อนๆ สูงไม่เท่ากัน มีช่องแหว่งสุ่ม
func _wall(body: StaticBody3D, center: Vector3, length: float, yaw: float, mat: Material) -> void:
	var dir := Vector3(cos(yaw), 0.0, -sin(yaw))   # ทิศตามแนวกำแพงในพิกัดของ body
	var t := -length * 0.5
	while t < length * 0.5 - 0.5:
		var seg := minf(_rng.randf_range(1.8, 3.6), length * 0.5 - t)
		if _rng.randf() < 0.18:
			t += seg
			continue
		var h := _rng.randf_range(1.2, 5.5)
		var pos := center + dir * (t + seg * 0.5) + Vector3(0.0, h * 0.5, 0.0)
		_add_box(body, Vector3(seg, h, 0.55), pos, yaw, mat)
		t += seg

# ---------------------------------------------------------------
# รถพัง
# ---------------------------------------------------------------
func _place_cars() -> void:
	var colors := [Color(0.42, 0.20, 0.12), Color(0.25, 0.27, 0.30), Color(0.34, 0.30, 0.17)]
	var dark := _mat(Color(0.07, 0.07, 0.08), 0.3)
	for i in car_count:
		var spot = _find_spot(3.2)
		if spot == null:
			continue
		var p: Vector2 = spot
		var body := _new_body(p, _rng.randf() * TAU)
		body.rotation.z = _rng.randf_range(-0.07, 0.07)
		var mat := _mat(colors[_rng.randi() % colors.size()], 0.3)

		_add_box(body, Vector3(4.3, 0.8, 1.9), Vector3(0.0, 0.65, 0.0), 0.0, mat, false)
		_add_box(body, Vector3(2.3, 0.75, 1.7), Vector3(-0.2, 1.4, 0.0), 0.0, mat, false)
		_add_box(body, Vector3(2.0, 0.45, 1.74), Vector3(-0.2, 1.42, 0.0), 0.0, dark, false)   # กระจก
		for x in [-1.4, 1.4]:
			for z in [-0.95, 0.95]:
				var w := _add_cyl(body, 0.38, 0.38, 0.3, Vector3(x, 0.38, z), dark)
				w.rotation.x = PI * 0.5
		_add_box_collision(body, Vector3(4.3, 1.8, 1.9), Vector3(0.0, 0.9, 0.0))

# ---------------------------------------------------------------
# เสาหัก
# ---------------------------------------------------------------
func _place_pillars() -> void:
	var mat := _mat(Color(0.38, 0.36, 0.34), 0.2)
	for i in pillar_count:
		var r := _rng.randf_range(0.5, 0.95)
		var spot = _find_spot(r + 0.4)
		if spot == null:
			continue
		var p: Vector2 = spot
		var h := _rng.randf_range(4.0, 11.0)
		var body := _new_body(p)
		_add_cyl(body, r * 0.92, r, h, Vector3(0.0, h * 0.5, 0.0), mat)
		_add_cyl_collision(body, r, h, Vector3(0.0, h * 0.5, 0.0))
		_add_box(body, Vector3(r * 2.6, 0.5, r * 2.6), Vector3(0.0, 0.25, 0.0), 0.0, mat, false)
		# ท่อนที่หักตกอยู่ข้างๆ
		_add_box(body, Vector3(r * 1.6, r * 1.4, r * 1.8), Vector3(r * 2.2, r * 0.7, 0.4), _rng.randf() * TAU, mat, false)

# ---------------------------------------------------------------
# ถังน้ำมัน / ถังไฟ
# ---------------------------------------------------------------
func _place_barrels() -> void:
	var colors := [Color(0.42, 0.20, 0.12), Color(0.22, 0.27, 0.32), Color(0.28, 0.30, 0.17)]
	for i in barrel_cluster_count:
		var spot = _find_spot(2.0)
		if spot == null:
			continue
		var p: Vector2 = spot
		var body := _new_body(p)
		for j in _rng.randi_range(2, 4):
			var off := Vector3(_rng.randf_range(-1.1, 1.1), 0.0, _rng.randf_range(-1.1, 1.1))
			var mat := _mat(colors[_rng.randi() % colors.size()], 0.5)
			_add_cyl(body, 0.38, 0.38, 1.0, off + Vector3(0.0, 0.5, 0.0), mat)
			_add_cyl_collision(body, 0.38, 1.0, off + Vector3(0.0, 0.5, 0.0))

# ถังไฟ: มีแสงส้มกะพริบ ให้แมพมีจุดสนใจและสว่างเป็นหย่อมๆ
func _place_fire_barrels() -> void:
	var rust := _mat(Color(0.30, 0.15, 0.09), 0.5)
	var flame_mat := StandardMaterial3D.new()
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.albedo_color = Color(1.0, 0.55, 0.12, 0.9)
	flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	for i in fire_barrel_count:
		var spot = _find_spot(1.5, 18.0, 120.0)
		if spot == null:
			continue
		var p: Vector2 = spot
		var body := _new_body(p)
		_add_cyl(body, 0.4, 0.4, 1.0, Vector3(0.0, 0.5, 0.0), rust)
		_add_cyl_collision(body, 0.4, 1.0, Vector3(0.0, 0.5, 0.0))

		var flame := _add_cyl(body, 0.0, 0.3, 0.8, Vector3(0.0, 1.4, 0.0), flame_mat)
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.55, 0.2)
		light.light_energy = 2.5
		light.omni_range = 14.0
		light.position = Vector3(0.0, 1.8, 0.0)
		body.add_child(light)

		# กะพริบ
		var d := _rng.randf_range(0.10, 0.18)
		var tw := create_tween().set_loops()
		tw.tween_property(light, "light_energy", _rng.randf_range(3.0, 3.6), d)
		tw.parallel().tween_property(flame, "scale", Vector3(1.0, 1.25, 1.0), d)
		tw.tween_property(light, "light_energy", _rng.randf_range(1.7, 2.2), d)
		tw.parallel().tween_property(flame, "scale", Vector3(1.0, 0.85, 1.0), d)

# ---------------------------------------------------------------
# ก้อนหิน
# ---------------------------------------------------------------
func _place_rocks() -> void:
	var shades := [Color(0.30, 0.27, 0.24), Color(0.25, 0.23, 0.21), Color(0.35, 0.30, 0.25)]
	for i in rock_count:
		var s := Vector3(_rng.randf_range(1.2, 4.0), _rng.randf_range(0.9, 3.2), _rng.randf_range(1.2, 4.0))
		var spot = _find_spot(maxf(s.x, s.z) * 0.7)
		if spot == null:
			continue
		var p: Vector2 = spot
		var body := _new_body(p, _rng.randf() * TAU)
		body.position.y = s.y * 0.3   # จมลงดินนิดหน่อย
		body.rotation.x = _rng.randf_range(-0.2, 0.2)
		body.rotation.z = _rng.randf_range(-0.2, 0.2)
		var mat := _mat(shades[_rng.randi() % shades.size()], 0.35)
		_add_box(body, s, Vector3.ZERO, 0.0, mat, true)
		# ก้อนเล็กซ้อนให้ดูไม่เป็นลูกบาศก์เกลี้ยงๆ
		_add_box(body, s * 0.6, Vector3(s.x * 0.28, s.y * 0.3, -s.z * 0.2), 0.7, mat, false)

# ---------------------------------------------------------------
# ต้นไม้ตาย
# ---------------------------------------------------------------
func _place_trees() -> void:
	var bark := _mat(Color(0.17, 0.13, 0.10), 0.5)
	for i in tree_count:
		var trunk_r := _rng.randf_range(0.18, 0.35)
		var h := _rng.randf_range(4.0, 8.0)
		var spot = _find_spot(trunk_r + 0.6)
		if spot == null:
			continue
		var p: Vector2 = spot
		var body := _new_body(p)
		_add_cyl(body, trunk_r * 0.45, trunk_r, h, Vector3(0.0, h * 0.5, 0.0), bark)
		_add_cyl_collision(body, trunk_r, h, Vector3(0.0, h * 0.5, 0.0))

		for j in _rng.randi_range(3, 5):
			var blen := _rng.randf_range(1.5, 3.0)
			var br := Node3D.new()
			br.position = Vector3(0.0, h * _rng.randf_range(0.45, 0.92), 0.0)
			br.rotation = Vector3(0.0, _rng.randf() * TAU, _rng.randf_range(0.6, 1.2))
			body.add_child(br)
			_add_cyl(br, 0.02, trunk_r * 0.35, blen, Vector3(0.0, blen * 0.5, 0.0), bark)

# ---------------------------------------------------------------
# พื้นผิวแต่งพื้น: หลุมระเบิด / เศษหิน
# ---------------------------------------------------------------
func _place_craters() -> void:
	var inner := _mat(Color(0.11, 0.085, 0.075), 0.1)
	var outer := _mat(Color(0.22, 0.16, 0.12), 0.1)
	for i in crater_count:
		var r := _rng.randf_range(3.0, 8.0)
		var a := _rng.randf() * TAU
		var d := sqrt(_rng.randf_range(clear_radius * clear_radius, decor_radius * decor_radius))
		var pos := Vector3(cos(a) * d, 0.0, sin(a) * d)

		var ring := _add_cyl(_decor, r * 1.3, r * 1.3, 0.02, pos + Vector3(0.0, 0.012, 0.0), outer)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var hole := _add_cyl(_decor, r, r, 0.04, pos + Vector3(0.0, 0.021, 0.0), inner)
		hole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

# เศษหินเล็กๆ ทั่วพื้น ใช้ MultiMesh (วาดทีเดียวทั้งหมด ไม่หนัก) ไม่มี collision
func _place_rubble() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	mm.mesh = bm
	mm.instance_count = rubble_count

	for i in rubble_count:
		var a := _rng.randf() * TAU
		var d := sqrt(_rng.randf_range(4.0, decor_radius * decor_radius))
		var s := Vector3(_rng.randf_range(0.2, 0.9), _rng.randf_range(0.1, 0.5), _rng.randf_range(0.2, 0.9))
		var e := Vector3(_rng.randf_range(-0.4, 0.4), _rng.randf() * TAU, _rng.randf_range(-0.4, 0.4))
		var b := Basis.from_euler(e) * Basis().scaled(s)
		mm.set_instance_transform(i, Transform3D(b, Vector3(cos(a) * d, s.y * 0.2, sin(a) * d)))

	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = _mat(Color(0.27, 0.24, 0.22), 0.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_decor.add_child(mi)

# ---------------------------------------------------------------
# เส้นขอบฟ้า: ซากเมืองไกลๆ (ไม่มี collision หมอกกลืนเป็นสีฟ้าอมส้ม)
# ---------------------------------------------------------------
func _build_skyline() -> void:
	var mat := _mat(Color(0.13, 0.12, 0.13), 0.02)
	for i in skyline_count:
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(380.0, 560.0)
		var s := Vector3(_rng.randf_range(18.0, 60.0), _rng.randf_range(30.0, 150.0), _rng.randf_range(18.0, 50.0))

		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = s
		mi.mesh = bm
		mi.material_override = mat
		mi.position = Vector3(cos(a) * d, s.y * 0.5 - 2.0, sin(a) * d)
		mi.rotation = Vector3(0.0, _rng.randf() * TAU, _rng.randf_range(-0.05, 0.05))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_decor.add_child(mi)

# ---------------------------------------------------------------
# ฝุ่น/เถ้าลอยรอบตัวผู้เล่น
# ---------------------------------------------------------------
func _spawn_dust(scene: Node) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		player = scene.find_child("Player", true, false)
	if player == null:
		return

	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.15, 0.85, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(30.0, 4.0, 30.0)
	pm.direction = Vector3(1.0, 0.1, 0.3)
	pm.spread = 40.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3(0.0, 0.05, 0.0)
	pm.scale_min = 0.5
	pm.scale_max = 1.4
	pm.color_ramp = gt

	var qm := QuadMesh.new()
	qm.size = Vector2(0.07, 0.07)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1.0, 0.75, 0.5, 0.7)
	qm.material = mat

	var ps := GPUParticles3D.new()
	ps.amount = 250
	ps.lifetime = 8.0
	ps.preprocess = 8.0
	ps.local_coords = false
	ps.visibility_aabb = AABB(Vector3(-40, -10, -40), Vector3(80, 30, 80))
	ps.process_material = pm
	ps.draw_pass_1 = qm
	ps.position = Vector3(0.0, 3.0, 0.0)
	ps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	player.add_child(ps)

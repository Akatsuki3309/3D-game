extends Node3D
# ===================================================================
# viewmodel.gd : ปืนเอเลี่ยน Sci-Fi ที่ผู้เล่นถืออยู่
#
# - สร้างโมเดลจากโค้ดทั้งหมด ไม่ต้องมีไฟล์ .glb / texture
# - วางเป็น "ลูกของ Camera3D" (ตัวที่มี weapon.gd) แล้วมันจะฟัง signal เอง
#   -> ไม่ต้องแก้ weapon.gd / player.gd เลย
# - ฟัง: ammo_changed, reload_started, reload_finished, dry_fire, died
#
# ท่าทาง: หายใจ / เดินโยก / เมาส์ลาก (lag) / วิ่ง / สไลด์ / กระโดด /
#         ยิงสะบัด + ปากกระบอกบาน + แฟลช / รีโหลด / ปืนชิดกำแพงดึงถอย / ตายแล้วปืนตก
# ปืนมี "ช่องพลังงาน" บนตัวปืน แสดงจำนวนกระสุนในแม็ก (ตาม mag_size ที่การ์ดอัปเกรด)
# ===================================================================

@export_group("Placement")
@export var rest_position := Vector3(0.18, -0.15, -0.36)   # ตำแหน่งปืนเทียบกล้อง (x ขวา, y ล่าง, z ไปข้างหน้า)
@export var rest_rotation_deg := Vector3(2.0, 5.0, 12.0)    # หมุนเริ่มต้น (องศา) y บวก = ปากกระบอกเอียงเข้าหากลางจอ
@export_range(0.3, 1.5) var model_scale := 0.78

@export_group("Colors")
@export var glow_color := Color(0.12, 1.0, 0.62)           # สีพลังงานปกติ
@export var warn_color := Color(1.0, 0.32, 0.08)           # สีตอนกระสุนใกล้หมด

@export_group("Motion")
@export_range(0.0, 2.0) var sway_amount := 1.0             # ปืนหน่วงตามการหันเมาส์ / เดินสไตรฟ์
@export_range(0.0, 2.0) var bob_amount := 1.0              # ปืนโยกตามก้าวเดิน
@export_range(0.0, 2.0) var kickback := 1.0                # แรงสะบัดตอนยิง

@export_group("Extras")
@export var core_light := true                              # แกนพลังงานเรืองแสงใส่สีให้ของรอบๆ นิดๆ
@export var wall_push := true                               # ชิดกำแพงปืนจะถอยเข้าหาตัว

# ปืน (Camera3D + weapon.gd) และผู้เล่น ไม่ระบุชนิด เพราะอ่านตัวแปรจากสคริปต์ของเรา
var weapon
var player

# ---------------- วัสดุ ----------------
var _shell: StandardMaterial3D     # เปลือกโลหะเข้ม
var _chitin: StandardMaterial3D    # ส่วนที่เป็นกระดูก/เปลือกแข็งสีอ่อนกว่า
var _glow_mat: StandardMaterial3D  # เส้นพลังงาน (เปลี่ยนสีตามกระสุน)
var _glass: StandardMaterial3D     # โดมแก้วครอบแกน
var _core_mat: ShaderMaterial
var _orb_mat: ShaderMaterial
var _flash_mat: StandardMaterial3D
var _cell_mats: Array[StandardMaterial3D] = []
var _cell_nodes: Array[MeshInstance3D] = []

# ---------------- ชิ้นส่วนที่ต้องขยับ ----------------
var _rail: Node3D
var _muzzle: Node3D
var _orb: MeshInstance3D
var _flash_quad: MeshInstance3D
var _flash_light: OmniLight3D
var _core_light: OmniLight3D
var _prong_pivots: Array[Node3D] = []
var _prong_axes: Array[Vector3] = []
var _unit_sphere: SphereMesh

# ---------------- สถานะ ----------------
var _mag := 0
var _mag_size := 7
var _last_mag := -1
var _reserve := 0

var _cur_color := Color.WHITE
var _flash := 0.0          # แฟลชปากกระบอก 0..1
var _pulse := 0.0          # แกนวาบ 0..1
var _fire_open := 0.0      # ปากกระบอกบานตอนยิง
var _open := 0.0           # ค่าบานปัจจุบัน (smooth)
var _since_shot := 99.0

var _kpos := Vector3.ZERO  # สปริงสะบัดตำแหน่ง (เมตร)
var _kvel := Vector3.ZERO
var _krot := Vector3.ZERO  # สปริงสะบัดหมุน (เรเดียน: pitch, yaw, roll)
var _krot_vel := Vector3.ZERO

var _look := Vector2.ZERO  # ความเร็วหันกล้องแบบ smooth (rad/s) x=yaw y=pitch
var _prev_yaw := 0.0
var _prev_pitch := 0.0
var _have_prev := false
var _strafe := Vector2.ZERO
var _amp := 0.0
var _own_phase := 0.0
var _air := 0.0

var _sprint_w := 0.0
var _slide_w := 0.0
var _equip := 0.0
var _dead := false
var _dead_w := 0.0
var _push := 0.0
var _push_target := 0.0

const BODY_SEMI := Vector3(0.046, 0.054, 0.19)
const BODY_CENTER_Z := -0.04
const MUZZLE_Z := -0.43
const PRONG_PIVOT_Z := -0.20
const PRONG_PROFILE := [Vector2(0.030, 0.0), Vector2(0.050, -0.06), Vector2(0.054, -0.15),
	Vector2(0.034, -0.24), Vector2(0.012, -0.31)]
const PRONG_RADII := [0.017, 0.014, 0.011, 0.0065, 0.0025]
const MAX_OPEN_RAD := 0.12      # ปากกระบอกบานสูงสุด (เรเดียน)
const CELL_STRIP_LEN := 0.13

const ENERGY_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, shadows_disabled;

uniform vec3 glow_color : source_color = vec3(0.12, 1.0, 0.62);
uniform float intensity = 2.5;
uniform float pulse = 0.0;
uniform float speed = 1.0;
uniform float bands = 7.0;
varying vec3 v_pos;

void vertex() {
	v_pos = VERTEX;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	float fres = pow(1.0 - clamp(dot(n, normalize(VIEW)), 0.0, 1.0), 2.5);
	float w = 0.5 + 0.5 * sin(v_pos.z * bands - TIME * 3.0 * speed + sin(v_pos.x * 5.0 + TIME) * 1.5);
	float breathe = 0.75 + 0.25 * sin(TIME * 2.2 * speed);
	float e = (0.45 + 0.55 * w) * breathe + fres * 1.6 + pulse * 2.5;
	ALBEDO = glow_color * 0.15;
	EMISSION = glow_color * intensity * e;
	ROUGHNESS = 0.2;
}
"""

# ===================================================================
# Setup
# ===================================================================
func _ready() -> void:
	weapon = get_parent()
	player = weapon.owner if weapon != null else null
	_cur_color = glow_color

	if weapon != null and "mag_size" in weapon:
		_mag_size = weapon.mag_size

	_make_materials()
	_build_gun()
	_rebuild_cells()

	if weapon != null:
		if weapon.has_signal("ammo_changed"):
			weapon.ammo_changed.connect(_on_ammo_changed)
		if weapon.has_signal("reload_started"):
			weapon.reload_started.connect(_on_reload_started)
		if weapon.has_signal("reload_finished"):
			weapon.reload_finished.connect(_on_reload_finished)
		if weapon.has_signal("dry_fire"):
			weapon.dry_fire.connect(_on_dry_fire)
	if player != null and player.has_signal("died"):
		player.died.connect(_on_player_died)

	# เริ่มเกม: ปืนยกขึ้นมาจากข้างล่าง
	position = rest_position
	scale = Vector3.ONE * model_scale

func _make_materials() -> void:
	_shell = StandardMaterial3D.new()
	_shell.albedo_color = Color(0.11, 0.15, 0.17)
	_shell.metallic = 0.5
	_shell.roughness = 0.4
	_shell.rim_enabled = true
	_shell.rim = 0.4
	_shell.rim_tint = 0.5

	_chitin = StandardMaterial3D.new()
	_chitin.albedo_color = Color(0.26, 0.22, 0.29)
	_chitin.metallic = 0.35
	_chitin.roughness = 0.45
	_chitin.clearcoat_enabled = true
	_chitin.clearcoat = 0.6
	_chitin.clearcoat_roughness = 0.25
	_chitin.rim_enabled = true
	_chitin.rim = 0.4
	_chitin.rim_tint = 0.6

	_glow_mat = StandardMaterial3D.new()
	_glow_mat.albedo_color = Color(0.0, 0.0, 0.0)
	_glow_mat.emission_enabled = true
	_glow_mat.emission = glow_color
	_glow_mat.emission_energy_multiplier = 2.5

	_glass = StandardMaterial3D.new()
	_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass.albedo_color = Color(0.5, 1.0, 0.85, 0.16)
	_glass.metallic = 0.0
	_glass.roughness = 0.05
	_glass.rim_enabled = true
	_glass.rim = 1.0
	_glass.rim_tint = 0.0

	var sh := Shader.new()
	sh.code = ENERGY_SHADER
	_core_mat = ShaderMaterial.new()
	_core_mat.shader = sh
	_core_mat.set_shader_parameter("intensity", 2.4)
	_core_mat.set_shader_parameter("bands", 9.0)
	_orb_mat = ShaderMaterial.new()
	_orb_mat.shader = sh
	_orb_mat.set_shader_parameter("intensity", 3.2)
	_orb_mat.set_shader_parameter("bands", 5.0)

	# แฟลชปากกระบอก: ภาพวงกลมเรืองแสง หันหน้าเข้ากล้องเสมอ
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	grad.set_color(1, Color(glow_color.r, glow_color.g, glow_color.b, 0.0))
	grad.add_point(0.3, Color(0.7, 1.0, 0.9, 0.7))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.albedo_texture = tex
	_flash_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_flash_mat.billboard_keep_scale = true
	_flash_mat.disable_receive_shadows = true

# ---------------------------------------------------------------
# ตัวช่วยสร้างชิ้นส่วน
# ---------------------------------------------------------------
func _mesh_node(mesh: Mesh, mat: Material, parent: Node3D, pos := Vector3.ZERO,
		rot_deg := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scl
	parent.add_child(mi)
	return mi

func _ellipsoid(parent: Node3D, center: Vector3, semi: Vector3, mat: Material,
		rot_deg := Vector3.ZERO) -> MeshInstance3D:
	if _unit_sphere == null:
		_unit_sphere = SphereMesh.new()
		_unit_sphere.radius = 1.0
		_unit_sphere.height = 2.0
		_unit_sphere.radial_segments = 32
		_unit_sphere.rings = 16
	return _mesh_node(_unit_sphere, mat, parent, center, rot_deg, semi)

func _tube(parent: Node3D, ctrl: PackedVector3Array, radii: PackedFloat32Array, mat: Material,
		sub := 8, sides := 12) -> MeshInstance3D:
	return _mesh_node(_curve_mesh(ctrl, radii, sub, sides), mat, parent)

# Catmull-Rom
static func _cr(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
			+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)

static func _dense(ctrl: PackedVector3Array, sub: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := ctrl.size()
	for s in n - 1:
		var p0 := ctrl[maxi(s - 1, 0)]
		var p1 := ctrl[s]
		var p2 := ctrl[s + 1]
		var p3 := ctrl[mini(s + 2, n - 1)]
		for k in sub:
			out.append(_cr(p0, p1, p2, p3, float(k) / sub))
	out.append(ctrl[n - 1])
	return out

# ท่อโค้งที่เรียวตามรัศมี (ใช้ทำกรงเล็บ สันหลัง ด้ามจับ ฯลฯ)
static func _curve_mesh(ctrl: PackedVector3Array, radii: PackedFloat32Array, sub: int, sides: int) -> ArrayMesh:
	var pts := _dense(ctrl, sub)
	var rpack := PackedVector3Array()
	for r in radii:
		rpack.append(Vector3(r, 0.0, 0.0))
	var rd := _dense(rpack, sub)
	var n := pts.size()

	var tans: Array[Vector3] = []
	for i in n:
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, n - 1)]
		tans.append((b - a).normalized())

	var up := Vector3.UP if absf(tans[0].dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var nrm := tans[0].cross(up).normalized()

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		if i > 0:
			var axis := tans[i - 1].cross(tans[i])
			if axis.length() > 0.0001:
				nrm = nrm.rotated(axis.normalized(), tans[i - 1].angle_to(tans[i]))
		nrm = (nrm - tans[i] * nrm.dot(tans[i])).normalized()
		var bin := tans[i].cross(nrm)
		var r := maxf(rd[i].x, 0.0005)
		for j in sides:
			var ang := TAU * float(j) / sides
			var dir := nrm * cos(ang) + bin * sin(ang)
			st.set_uv(Vector2(float(j) / sides, float(i) / (n - 1)))
			st.add_vertex(pts[i] + dir * r)
	for i in n - 1:
		for j in sides:
			var j2 := (j + 1) % sides
			var a := i * sides + j
			var b := i * sides + j2
			var c := (i + 1) * sides + j
			var d := (i + 1) * sides + j2
			# Godot: ด้านหน้า = หมุนตามเข็มนาฬิกา
			st.add_index(a)
			st.add_index(c)
			st.add_index(b)
			st.add_index(b)
			st.add_index(c)
			st.add_index(d)
	st.generate_normals()
	return st.commit()

# ผิวด้านข้างของลำตัวที่ความสูง y, ตำแหน่ง z (ไว้วางเส้นพลังงาน/ครีบให้แนบตัว)
func _body_x(z: float, y: float) -> float:
	var u := (z - BODY_CENTER_Z) / BODY_SEMI.z
	var v := y / BODY_SEMI.y
	return BODY_SEMI.x * sqrt(maxf(1.0 - u * u - v * v, 0.0))

# ===================================================================
# สร้างตัวปืน (หันปากกระบอกไปทาง -Z)
# ===================================================================
func _build_gun() -> void:
	# --- ลำตัวหลัก ---
	_ellipsoid(self, Vector3(0, 0, BODY_CENTER_Z), BODY_SEMI, _shell)
	_ellipsoid(self, Vector3(0, -0.002, 0.15), Vector3(0.038, 0.045, 0.075), _chitin)
	_ellipsoid(self, Vector3(0, 0, -0.205), Vector3(0.037, 0.041, 0.085), _chitin)
	_ellipsoid(self, Vector3(0, -0.045, -0.02), Vector3(0.022, 0.028, 0.125), _chitin)

	# --- สันหลังคู่ครอบแกนพลังงาน (เหมือนซี่โครง) ---
	for side in [-1.0, 1.0]:
		_tube(self,
			PackedVector3Array([
				Vector3(side * 0.024, 0.040, 0.14), Vector3(side * 0.034, 0.058, 0.04),
				Vector3(side * 0.033, 0.060, -0.10), Vector3(side * 0.020, 0.044, -0.25)]),
			PackedFloat32Array([0.013, 0.016, 0.013, 0.006]), _chitin)

	# --- แกนพลังงานใต้โดมแก้ว ---
	_ellipsoid(self, Vector3(0, 0.045, -0.095), Vector3(0.017, 0.017, 0.05), _core_mat)
	_ellipsoid(self, Vector3(0, 0.044, -0.095), Vector3(0.028, 0.027, 0.066), _glass)
	if core_light:
		_core_light = OmniLight3D.new()
		_core_light.position = Vector3(0, 0.07, -0.095)
		_core_light.omni_range = 1.3
		_core_light.light_energy = 0.35
		_core_light.light_color = glow_color
		_core_light.shadow_enabled = false
		add_child(_core_light)

	# --- รางช่องพลังงาน (แสดงจำนวนกระสุนในแม็ก) ---
	_rail = Node3D.new()
	_rail.position = Vector3(0, 0.050, 0.065)
	add_child(_rail)
	_mesh_node(_box(Vector3(0.016, 0.006, CELL_STRIP_LEN + 0.02)), _chitin, _rail)

	# --- เส้นพลังงานแนบข้างลำตัว + ครีบเหงือก ---
	for side in [-1.0, 1.0]:
		var vein := PackedVector3Array()
		for z in [0.12, 0.07, 0.0, -0.07, -0.13, -0.19]:
			var y: float = 0.006 + 0.008 * sin(z * 30.0)
			vein.append(Vector3(side * (_body_x(z, y) + 0.0012), y, z))
		_tube(self, vein, PackedFloat32Array([0.0032, 0.0035, 0.0035, 0.0035, 0.003, 0.0028]), _glow_mat, 6, 8)

		for z in [0.07, 0.03, -0.01, -0.05, -0.09]:
			var y := -0.012
			var x := _body_x(z, y)
			_ellipsoid(self, Vector3(side * (x + 0.003), y, z), Vector3(0.0045, 0.028, 0.0095),
				_chitin, Vector3(0, 0, side * -22.0))

	# --- เสาเซนเซอร์ด้านบน (ใช้เป็นศูนย์เล็งไปในตัว) ---
	_tube(self,
		PackedVector3Array([Vector3(0, 0.046, -0.20), Vector3(0, 0.072, -0.27), Vector3(0, 0.094, -0.33)]),
		PackedFloat32Array([0.006, 0.0038, 0.0016]), _chitin, 6, 8)
	_ellipsoid(self, Vector3(0, 0.095, -0.335), Vector3(0.0045, 0.0045, 0.0045), _glow_mat)

	# --- ด้ามจับ + โครงไกปืนแบบกรงเล็บ ---
	_tube(self,
		PackedVector3Array([Vector3(0, -0.035, 0.05), Vector3(0, -0.095, 0.085),
			Vector3(0, -0.155, 0.115), Vector3(0, -0.205, 0.125)]),
		PackedFloat32Array([0.028, 0.025, 0.022, 0.017]), _chitin)
	_tube(self,
		PackedVector3Array([Vector3(0, -0.045, -0.035), Vector3(0, -0.088, -0.03),
			Vector3(0, -0.098, 0.02), Vector3(0, -0.078, 0.06)]),
		PackedFloat32Array([0.0065, 0.0062, 0.006, 0.0058]), _chitin, 8, 8)
	_tube(self,
		PackedVector3Array([Vector3(0, -0.045, 0.025), Vector3(0, -0.07, 0.018), Vector3(0, -0.08, 0.026)]),
		PackedFloat32Array([0.005, 0.0045, 0.0035]), _glow_mat, 6, 8)

	# --- หางหลัง (ให้ปืนดูเป็นสิ่งมีชีวิต) ---
	_tube(self,
		PackedVector3Array([Vector3(0, 0.012, 0.19), Vector3(0, 0.03, 0.235), Vector3(0, 0.015, 0.28)]),
		PackedFloat32Array([0.022, 0.014, 0.004]), _chitin, 6, 10)

	# --- ปากกระบอก 3 กรงเล็บ + ลูกพลาสม่า ---
	_build_muzzle()

func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b

func _build_muzzle() -> void:
	var angles := [30.0, 150.0, 270.0]
	for a_deg in angles:
		var a := deg_to_rad(a_deg)
		var radial := Vector3(cos(a), sin(a), 0.0)

		var pivot := Node3D.new()
		pivot.position = Vector3(0, 0, PRONG_PIVOT_Z)
		add_child(pivot)
		_prong_pivots.append(pivot)
		_prong_axes.append(Vector3(-sin(a), cos(a), 0.0))

		var ctrl := PackedVector3Array()
		for p in PRONG_PROFILE:
			ctrl.append(radial * p.x + Vector3(0, 0, p.y))
		_tube(pivot, ctrl, PackedFloat32Array(PRONG_RADII), _chitin, 8, 12)
		# ปลายกรงเล็บเรืองแสง
		_ellipsoid(pivot, ctrl[ctrl.size() - 1], Vector3(0.0065, 0.0065, 0.0065), _glow_mat)

	# ก้านปล่อยพลังงานเชื่อมลำตัวไปถึงลูกพลาสม่า
	_tube(self,
		PackedVector3Array([Vector3(0, 0, -0.24), Vector3(0, 0, -0.33), Vector3(0, 0, MUZZLE_Z + 0.012)]),
		PackedFloat32Array([0.013, 0.008, 0.0035]), _chitin, 6, 10)

	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0, 0, MUZZLE_Z)
	add_child(_muzzle)

	_orb = _ellipsoid(_muzzle, Vector3.ZERO, Vector3(0.019, 0.019, 0.019), _orb_mat)

	_flash_quad = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	_flash_quad.mesh = q
	_flash_quad.material_override = _flash_mat
	_flash_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash_quad.visible = false
	_muzzle.add_child(_flash_quad)

	_flash_light = OmniLight3D.new()
	_flash_light.omni_range = 7.0
	_flash_light.light_energy = 0.0
	_flash_light.light_color = glow_color
	_flash_light.shadow_enabled = false
	_muzzle.add_child(_flash_light)

# ช่องพลังงานต่อกระสุนหนึ่งนัด (สร้างใหม่เมื่อ mag_size เปลี่ยน เช่นเลือกการ์ดเพิ่มแม็ก)
func _rebuild_cells() -> void:
	for c in _cell_nodes:
		c.queue_free()
	_cell_nodes.clear()
	_cell_mats.clear()

	var n := maxi(_mag_size, 1)
	var spacing := CELL_STRIP_LEN / n
	var length := minf(spacing * 0.78, 0.04)
	for i in n:
		var z := CELL_STRIP_LEN * 0.5 - (i + 0.5) * spacing   # ช่องแรกอยู่ท้ายปืน
		var mat := StandardMaterial3D.new()
		mat.emission_enabled = true
		var mi := _mesh_node(_box(Vector3(0.0105, 0.005, length)), mat, _rail, Vector3(0, 0.004, z))
		_cell_nodes.append(mi)
		_cell_mats.append(mat)

# ===================================================================
# Signals จาก weapon.gd / player.gd
# ===================================================================
func _on_ammo_changed(mag: int, mag_size: int, reserve: int) -> void:
	_mag = mag
	_reserve = reserve
	if mag_size != _mag_size:
		_mag_size = mag_size
		_rebuild_cells()
	if _last_mag >= 0 and mag < _last_mag:
		_on_fired()
	_last_mag = mag

func _on_fired() -> void:
	_since_shot = 0.0
	_flash = 1.0
	_pulse = 1.0
	_fire_open = 1.0
	var k := kickback
	_kvel += Vector3(randf_range(-0.08, 0.08), randf_range(-0.04, 0.12), 2.1) * k
	_krot_vel += Vector3(5.5 * randf_range(0.85, 1.2), randf_range(-1.4, 1.4), randf_range(-2.2, 2.2)) * k
	if _flash_quad != null:
		_flash_quad.rotation.z = randf() * TAU

func _on_dry_fire() -> void:
	_kvel += Vector3(0.0, -0.1, 0.35) * kickback
	_krot_vel += Vector3(1.2, 0.0, randf_range(-1.0, 1.0)) * kickback
	_pulse = maxf(_pulse, 0.5)

func _on_reload_started(_duration: float) -> void:
	_kvel += Vector3(-0.05, -0.5, 0.1)
	_krot_vel += Vector3(-1.5, 0.0, 1.0)

func _on_reload_finished() -> void:
	_kvel += Vector3(0.0, 0.08, 0.9) * kickback
	_krot_vel += Vector3(2.4, 0.0, 0.0) * kickback
	_pulse = 1.0

func _on_player_died() -> void:
	_dead = true

# ตำแหน่งปากกระบอกในโลก (ไว้ใช้ทำ Tracer / เอฟเฟกต์ในอนาคต)
func get_muzzle_global_position() -> Vector3:
	return _muzzle.global_position if _muzzle != null else global_position

# ===================================================================
# ตรวจกำแพงใกล้ตัว (ปืนจะได้ไม่ทะลุกำแพง)
# ===================================================================
func _physics_process(_delta: float) -> void:
	if not wall_push or weapon == null or player == null:
		_push_target = 0.0
		return
	var cam: Camera3D = weapon
	var reach := 0.34 + 0.52 * model_scale
	var from := cam.global_position
	var to := from - cam.global_transform.basis.z * reach
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		_push_target = 0.0
	else:
		_push_target = clampf((reach - from.distance_to(hit.position)) / reach, 0.0, 1.0)

# ===================================================================
# Animation
# ===================================================================
func _process(delta: float) -> void:
	if player == null or weapon == null:
		return
	delta = minf(delta, 0.05)
	var t := Time.get_ticks_msec() / 1000.0

	# ----- อ่านสถานะผู้เล่น -----
	var vel: Vector3 = player.velocity
	var h_speed := Vector2(vel.x, vel.z).length()
	var grounded: bool = player.is_on_floor()
	var sliding: bool = player.is_sliding
	var sprinting: bool = player.is_sprinting and h_speed > 8.0 and not sliding

	_since_shot += delta
	var reloading: bool = weapon.is_reloading()
	var rprog: float = weapon.reload_progress() if reloading else 0.0

	# ----- สปริงสะบัด (ตำแหน่ง / หมุน) -----
	_kvel += (-190.0 * _kpos - 17.0 * _kvel) * delta
	_kpos += _kvel * delta
	_krot_vel += (-190.0 * _krot - 17.0 * _krot_vel) * delta
	_krot += _krot_vel * delta

	# ----- ปืนหน่วงตามการหันกล้อง -----
	var yaw: float = player.rotation.y
	var pitch: float = player.head.rotation.x
	if not _have_prev:
		_prev_yaw = yaw
		_prev_pitch = pitch
		_have_prev = true
	var w_yaw := clampf(wrapf(yaw - _prev_yaw, -PI, PI) / maxf(delta, 0.0001), -10.0, 10.0)
	var w_pitch := clampf((pitch - _prev_pitch) / maxf(delta, 0.0001), -10.0, 10.0)
	_prev_yaw = yaw
	_prev_pitch = pitch
	_look = _look.lerp(Vector2(w_yaw, w_pitch), 1.0 - exp(-12.0 * delta))

	var local_vel: Vector3 = player.global_transform.basis.inverse() * vel
	_strafe = _strafe.lerp(Vector2(local_vel.x, local_vel.z) / 12.0, 1.0 - exp(-7.0 * delta))

	# ----- โยกตามก้าวเดิน (ใช้เฟสเดียวกับกล้อง ถ้าอ่านได้) -----
	var amp_target := 0.0
	if grounded and not sliding:
		amp_target = clampf(h_speed / 12.0, 0.0, 1.0)
	_amp = lerpf(_amp, amp_target, 1.0 - exp(-8.0 * delta))
	var phase: float
	var p_phase = player.get("_step_phase")
	if p_phase != null:
		phase = p_phase
	else:
		if grounded and h_speed > 0.1 and not sliding:
			_own_phase = fmod(_own_phase + (4.0 + h_speed * 0.6) * delta, TAU)
		phase = _own_phase

	# ----- น้ำหนักท่าทางต่างๆ -----
	var sprint_target := 1.0 if (sprinting and _since_shot > 0.3 and not reloading) else 0.0
	_sprint_w = lerpf(_sprint_w, sprint_target, 1.0 - exp(-9.0 * delta))
	_slide_w = lerpf(_slide_w, 1.0 if sliding else 0.0, 1.0 - exp(-10.0 * delta))
	var air_target := 0.0
	if not grounded:
		air_target = clampf(-vel.y * 0.004, -0.03, 0.03)
	_air = lerpf(_air, air_target, 1.0 - exp(-8.0 * delta))

	_equip = move_toward(_equip, 1.0, delta / 0.7)
	_dead_w = move_toward(_dead_w, 1.0 if _dead else 0.0, delta / 0.45)
	_push = lerpf(_push, _push_target, 1.0 - exp(-14.0 * delta))

	var r_w := 0.0
	if reloading:
		r_w = smoothstep(0.0, 0.16, rprog) * (1.0 - smoothstep(0.84, 1.0, rprog))

	# ----- รวมตำแหน่ง / การหมุน -----
	var pos := rest_position
	var rot := Vector3(deg_to_rad(rest_rotation_deg.x), deg_to_rad(rest_rotation_deg.y), deg_to_rad(rest_rotation_deg.z))

	# หายใจ
	var idle := 1.0 - _amp
	pos.y += sin(t * 1.6) * 0.0016 * idle
	rot.x += sin(t * 1.1) * 0.004 * idle

	# เดินโยก
	pos.x += sin(phase) * 0.010 * _amp * bob_amount
	pos.y += -cos(phase * 2.0) * 0.007 * _amp * bob_amount
	rot.z += sin(phase) * deg_to_rad(1.6) * _amp * bob_amount
	rot.x += sin(phase * 2.0) * deg_to_rad(1.0) * _amp * bob_amount

	# เมาส์ลาก / สไตรฟ์ / กระโดด
	pos.x += clampf(_look.x * 0.012, -0.05, 0.05) * sway_amount
	pos.y += clampf(-_look.y * 0.012, -0.05, 0.05) * sway_amount
	rot.y += clampf(-_look.x * 0.02, -0.12, 0.12) * sway_amount
	rot.x += clampf(-_look.y * 0.015, -0.1, 0.1) * sway_amount
	rot.z += clampf(_look.x * 0.012, -0.08, 0.08) * sway_amount
	pos.x += -_strafe.x * 0.025 * sway_amount
	pos.z += _strafe.y * 0.012 * sway_amount
	pos.y += _air

	# วิ่ง
	pos += Vector3(-0.05, -0.06, 0.035) * _sprint_w
	rot += Vector3(deg_to_rad(-9.0), deg_to_rad(24.0), deg_to_rad(-14.0)) * _sprint_w

	# สไลด์
	pos += Vector3(0.025, -0.035, 0.02) * _slide_w
	rot += Vector3(deg_to_rad(4.0), deg_to_rad(-7.0), deg_to_rad(18.0)) * _slide_w

	# รีโหลด: ปืนเอียงเอาด้านบนที่มีช่องพลังงานให้ผู้เล่นเห็น
	pos += Vector3(-0.055, -0.065, 0.03) * r_w
	rot += Vector3(deg_to_rad(-16.0), deg_to_rad(12.0), deg_to_rad(34.0)) * r_w
	pos.x += sin(rprog * 38.0) * 0.0025 * r_w

	# ยกปืนตอนเริ่มเกม / ปืนตกตอนตาย
	var eq := pow(1.0 - _equip, 2.0)
	pos += Vector3(0.0, -0.32, 0.05) * eq
	rot.x -= deg_to_rad(55.0) * eq
	pos += Vector3(0.05, -0.45, 0.05) * _dead_w
	rot += Vector3(deg_to_rad(-40.0), 0.0, deg_to_rad(25.0)) * _dead_w

	# ชิดกำแพง
	pos += Vector3(0.0, -0.04, 0.34) * _push
	rot.x += _push * 0.9
	rot.y += _push * 0.25

	# สะบัดตอนยิง
	pos += _kpos
	rot += _krot

	position = pos
	rotation = rot
	scale = Vector3.ONE * model_scale

	_animate_parts(delta, r_w, rprog, reloading)

# ===================================================================
# ส่วนที่ขยับ / เรืองแสง
# ===================================================================
func _animate_parts(delta: float, r_w: float, rprog: float, reloading: bool) -> void:
	# --- จำนวนช่องพลังงานที่โชว์ (ตอนรีโหลดค่อยๆ เติมตามความคืบหน้า) ---
	var shown := float(_mag)
	if reloading:
		var target := mini(_mag_size, _mag + _reserve)
		shown = lerpf(float(_mag), float(target), rprog)
	var ratio := clampf(shown / maxf(float(_mag_size), 1.0), 0.0, 1.0)

	# --- สีพลังงาน: เต็ม = เขียวอมฟ้า, ใกล้หมด = ส้มแดง ---
	var warn := 1.0 - smoothstep(0.0, 0.4, ratio)
	var target_col := glow_color.lerp(warn_color, warn)
	_cur_color = _cur_color.lerp(target_col, 1.0 - exp(-8.0 * delta))

	_flash = move_toward(_flash, 0.0, delta * 13.0)
	_pulse = move_toward(_pulse, 0.0, delta * 3.5)
	_fire_open = move_toward(_fire_open, 0.0, delta * 6.0)

	# --- วัสดุแกน / ลูกพลาสม่า ---
	var speed := 1.0 + 1.6 * warn + (1.5 if reloading else 0.0)
	var pulse := _pulse * 0.6 + _flash * 0.8 + r_w * 0.25
	for m in [_core_mat, _orb_mat]:
		m.set_shader_parameter("glow_color", _cur_color)
		m.set_shader_parameter("pulse", pulse)
		m.set_shader_parameter("speed", speed)
	_glow_mat.emission = _cur_color
	_glow_mat.emission_energy_multiplier = 2.3 + _pulse * 1.5 + _flash * 1.5
	_glass.albedo_color = Color(_cur_color.r * 0.5 + 0.3, _cur_color.g * 0.5 + 0.3, _cur_color.b * 0.5 + 0.3, 0.16)

	# --- ช่องพลังงาน ---
	for i in _cell_mats.size():
		var b := clampf(shown - float(i), 0.0, 1.0)
		var m := _cell_mats[i]
		m.albedo_color = Color(0.02, 0.025, 0.03).lerp(_cur_color * 0.35, b)
		m.emission = _cur_color
		m.emission_energy_multiplier = 0.04 + b * (2.8 + _pulse * 1.5)

	# --- ปากกระบอกบาน (ตอนยิง / รีโหลด) ---
	var open_target := _fire_open * 0.9 + r_w * 0.6
	_open = lerpf(_open, open_target, 1.0 - exp(-20.0 * delta))
	for i in _prong_pivots.size():
		_prong_pivots[i].basis = Basis(_prong_axes[i], -_open * MAX_OPEN_RAD)

	# --- แฟลช + แสง ---
	if _orb != null:
		var s := 0.019 * (1.0 + 1.1 * _flash + 0.25 * r_w)
		_orb.scale = Vector3(s, s, s)
	if _flash_quad != null:
		_flash_quad.visible = _flash > 0.03
		var fs := 0.42 * _flash
		_flash_quad.scale = Vector3(fs, fs, fs)
	if _flash_light != null:
		_flash_light.light_color = _cur_color
		_flash_light.light_energy = 3.0 * _flash
	if _core_light != null:
		_core_light.light_color = _cur_color
		_core_light.light_energy = 0.3 + 0.5 * _pulse + 0.2 * r_w

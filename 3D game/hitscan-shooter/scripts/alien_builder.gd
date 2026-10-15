class_name AlienBuilder
extends RefCounted

# ตัวช่วยสร้างโมเดลเอเลี่ยนจากโค้ด (สไตล์เดียวกับปืนใน viewmodel.gd)
# - ellipsoid : ก้อนรี (ลำตัว หัว ตา ข้อต่อ)
# - tube      : ท่อโค้งเรียว (ขา แขน กรงเล็บ คอ) ใส่ cache_key เพื่อใช้มิติซ้ำ ไม่ต้องสร้างใหม่ทุกตัวที่เกิด
# - cone      : หนามแหลม / ผลึก
# - pivot     : Node3D จุดหมุนข้อต่อ (ไว้ให้ขา/แขนแกว่ง)

static var _unit_sphere: SphereMesh
static var _mesh_cache := {}

# ---------------------------------------------------------------
# วัสดุ
# ---------------------------------------------------------------
static func shell_material(color: Color, metallic := 0.4, roughness := 0.45) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	m.rim_enabled = true
	m.rim = 0.4
	m.rim_tint = 0.5
	# เปิด emission ไว้ก่อน (ค่า 0) enemy_base ใช้เรืองตอนง้างโจมตี
	m.emission_enabled = true
	m.emission = Color.BLACK
	m.emission_energy_multiplier = 0.0
	return m

static func glow_material(color: Color, energy := 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.0, 0.0, 0.0)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m

# ---------------------------------------------------------------
# ชิ้นส่วน
# ---------------------------------------------------------------
static func node(mesh: Mesh, mat: Material, parent: Node3D, pos := Vector3.ZERO,
		rot_deg := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scl
	parent.add_child(mi)
	return mi

static func pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n

static func ellipsoid(parent: Node3D, center: Vector3, semi: Vector3, mat: Material,
		rot_deg := Vector3.ZERO) -> MeshInstance3D:
	if _unit_sphere == null:
		_unit_sphere = SphereMesh.new()
		_unit_sphere.radius = 1.0
		_unit_sphere.height = 2.0
		_unit_sphere.radial_segments = 20
		_unit_sphere.rings = 10
	return node(_unit_sphere, mat, parent, center, rot_deg, semi)

static func tube(parent: Node3D, ctrl: PackedVector3Array, radii: PackedFloat32Array, mat: Material,
		sub := 6, sides := 10, cache_key := "") -> MeshInstance3D:
	var mesh: Mesh
	if cache_key != "" and _mesh_cache.has(cache_key):
		mesh = _mesh_cache[cache_key]
	else:
		mesh = _curve_mesh(ctrl, radii, sub, sides)
		if cache_key != "":
			_mesh_cache[cache_key] = mesh
	return node(mesh, mat, parent)

# หนามแหลม: ฐานอยู่ที่ base ปลายชี้ไปทาง dir
static func cone(parent: Node3D, base: Vector3, dir: Vector3, radius: float, length: float,
		mat: Material) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = radius
	cm.height = length
	cm.radial_segments = 8
	cm.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = mat
	var d := dir.normalized()
	mi.position = base + d * (length * 0.5)
	mi.basis = Basis(Quaternion(Vector3.UP, d))
	parent.add_child(mi)
	return mi

# ---------------------------------------------------------------
# ท่อโค้งเรียว (Catmull-Rom) เหมือนใน viewmodel.gd
# ---------------------------------------------------------------
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
			st.add_index(a)
			st.add_index(c)
			st.add_index(b)
			st.add_index(b)
			st.add_index(c)
			st.add_index(d)
	st.generate_normals()
	return st.commit()

class_name EnemyProjectile
extends Area3D

# กระสุนของมอนตีไกล: พุ่งตรงด้วยความเร็วจริง (ต่างจากปืนผู้เล่นที่เป็น hitscan) ผู้เล่นจึงหลบได้
# สร้างตัวเองจากโค้ดทั้งหมด ไม่ต้องมี scene

var velocity := Vector3.ZERO
var damage := 10.0
var shooter: Node

var _life := 6.0

func setup(from: Node, vel: Vector3, dmg: float) -> void:
	shooter = from
	velocity = vel
	damage = dmg

func _ready() -> void:
	collision_layer = 0
	collision_mask = 1

	var shape := SphereShape3D.new()
	shape.radius = 0.3
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.7, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.0)
	mat.emission_energy_multiplier = 2.0
	var mesh := SphereMesh.new()
	mesh.radius = 0.2
	mesh.height = 0.4
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)

	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	global_position += velocity * delta
	_life -= delta
	if _life <= 0.0:
		queue_free()

func _on_body_entered(body: Node3D) -> void:
	if body == shooter or body is EnemyBase:
		return   # ทะลุมอนด้วยกัน
	if body is CharacterBody3D and body.has_method("take_damage"):
		body.take_damage(damage)
	queue_free()

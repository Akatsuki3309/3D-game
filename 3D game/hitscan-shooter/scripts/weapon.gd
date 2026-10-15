extends Camera3D

# mag = กระสุนในแม็ก, reserve = กระสุนสำรอง (HUD/สคริปต์อื่นฟัง signal นี้)
signal ammo_changed(mag: int, mag_size: int, reserve: int)
signal reload_started(duration: float)
signal reload_finished
signal dry_fire   # กดยิงตอนกระสุนหมด (ไว้ใส่เสียงคลิกทีหลัง)

@export var max_range: float = 500.0
@export var bullet_speed: float = 250.0
@export var damage: float = 50
@export var fire_rate: float = 0.35
@export var impact_scene: PackedScene

@export_group("Ammo")
@export var mag_size := 7              # กระสุนต่อแม็ก
@export var start_reserve := 35        # กระสุนสำรองตอนเริ่มเกม
@export var max_reserve := 70          # เก็บสำรองได้สูงสุด
@export var reload_time := 1.6         # วินาที
@export var auto_reload := true        # แม็กหมดแล้วรีโหลดเอง

@export_group("Recoil")
@export var kick_pitch: float = 6.0     # สะบัดภาพขึ้น จุดสูงสุด (องศา)
@export var kick_yaw: float = 2.4       # ส่ายซ้ายขวาของภาพ ± (องศา)
@export var kick_roll: float = 3.0      # เอียงกล้อง ± (องศา)
@export var aim_pitch: float = 2.0      # ปลายกระบอกเด้งจริงต่อนัด
@export var aim_yaw: float = 0.5        # ปลายกระบอกส่ายจริง ± ต่อนัด
@export var wander: float = 0.6         # 0 = สุ่มล้วน, 1 = เอียงไปทางเดิมต่อเนื่อง
@export var recoil_reset_time: float = 0.35

@onready var player: CharacterBody3D = owner

var mag := 0
var reserve := 0

var _cooldown := 0.0
var _since_last_shot := 999.0
var _bias := 0.0   # ทิศที่ปืนกำลังเตะไป (-1..1) เปลี่ยนช้าๆ ระหว่างยิงรัว

var _reloading := false
var _reload_left := 0.0

func _ready() -> void:
	mag = mag_size
	reserve = start_reserve
	emit_state()

# HUD เรียกตอนเริ่ม เพราะ _ready ของเรารันก่อน HUD จะเชื่อม signal ทัน
func emit_state() -> void:
	ammo_changed.emit(mag, mag_size, reserve)

func is_reloading() -> bool:
	return _reloading

# 0..1 ความคืบหน้าการรีโหลด
func reload_progress() -> float:
	if not _reloading or reload_time <= 0.0:
		return 0.0
	return clampf(1.0 - _reload_left / reload_time, 0.0, 1.0)

func _process(delta: float) -> void:
	_cooldown -= delta
	_since_last_shot += delta

	if _reloading:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_finish_reload()
		return   # รีโหลดอยู่ ยิงไม่ได้

	if InputMap.has_action("reload") and Input.is_action_just_pressed("reload") \
	and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		start_reload()
		return

	if Input.is_action_pressed("shoot") \
	and _cooldown <= 0.0 \
	and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_cooldown = fire_rate
		if mag > 0:
			shoot()
		else:
			dry_fire.emit()
			if auto_reload:
				start_reload()

# ---------------------------------------------------------------
# Ammo
# ---------------------------------------------------------------
func start_reload() -> void:
	if _reloading or mag >= mag_size or reserve <= 0:
		return
	_reloading = true
	_reload_left = reload_time
	reload_started.emit(reload_time)

func _finish_reload() -> void:
	_reloading = false
	var take := mini(mag_size - mag, reserve)
	mag += take
	reserve -= take
	ammo_changed.emit(mag, mag_size, reserve)
	reload_finished.emit()

# ของดรอป/ร้านค้าเรียกใช้ คืนจำนวนที่เก็บได้จริง (0 = เต็มแล้ว เก็บไม่ได้)
func add_ammo(amount: int) -> int:
	var accepted := mini(amount, max_reserve - reserve)
	if accepted <= 0:
		return 0
	reserve += accepted
	ammo_changed.emit(mag, mag_size, reserve)
	return accepted

# ---------------------------------------------------------------
# Shooting
# ---------------------------------------------------------------
func shoot() -> void:
	mag -= 1
	ammo_changed.emit(mag, mag_size, reserve)

	var space := get_world_3d().direct_space_state
	var from := global_position
	var to := from + -global_transform.basis.z * max_range

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [player.get_rid()]
	var result := space.intersect_ray(query)

	_fire_recoil()

	# ยิงนัดสุดท้ายแล้วรีโหลดต่อเอง
	if mag <= 0 and auto_reload:
		start_reload()

	if result.is_empty():
		return

	var hit_pos: Vector3 = result.position
	var hit_normal: Vector3 = result.normal
	var collider_id: int = result.collider.get_instance_id()

	var travel_time := from.distance_to(hit_pos) / bullet_speed
	await get_tree().create_timer(travel_time, false).timeout

	if not is_inside_tree():
		return
	_apply_hit(collider_id, hit_pos, hit_normal)

func _fire_recoil() -> void:
	# หยุดยิงพักหนึ่ง = ทิศเตะรีเซ็ต
	if _since_last_shot > recoil_reset_time:
		_bias = randf_range(-1.0, 1.0)
	_since_last_shot = 0.0

	# ทิศเตะค่อยๆ เดินสุ่ม ไม่กระโดดมั่ว
	_bias = clampf(_bias + randf_range(-0.5, 0.5), -1.0, 1.0)
	var dir := lerpf(randf_range(-1.0, 1.0), _bias, wander)

	player.apply_recoil(
		kick_pitch * randf_range(0.8, 1.25),
		kick_yaw * dir,
		kick_roll * dir * randf_range(0.6, 1.2),
		aim_pitch * randf_range(0.8, 1.2),
		aim_yaw * dir
	)

func _apply_hit(collider_id: int, pos: Vector3, _normal: Vector3) -> void:
	var collider := instance_from_id(collider_id)
	if is_instance_valid(collider) and collider.has_method("take_damage"):
		collider.take_damage(damage)

	if impact_scene:
		var fx: Node3D = impact_scene.instantiate()
		get_tree().current_scene.add_child(fx)
		fx.global_position = pos

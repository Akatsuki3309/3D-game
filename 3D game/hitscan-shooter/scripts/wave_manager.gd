class_name WaveManager
extends Node

# ระบบ Wave: เกิดมอนเป็นรอบๆ เคลียร์หมดแล้วขึ้น Wave ถัดไป เล่นได้ไม่รู้จบ
# - Wave แรกมอน 5 ตัว สุ่มชนิด (ตีใกล้ / ยิงไกล / AOE) ตามน้ำหนักที่ตั้งไว้
# - ค่าสถานะโตแบบ "โค้งชะลอ" ไม่ใช่ทวีคูณ (ดูฟังก์ชัน hp_mult / damage_mult / speed_mult)
# - จำกัดจำนวนมอนที่อยู่พร้อมกัน (max_alive) ที่เหลือทยอยเกิดตามมา
# - สร้าง GUI (WaveHUD) ให้เองในโค้ด ไม่ต้องลาก node
#
# ระบบการ์ด (use_cards): เคลียร์ Wave แล้วหยุดรอ UpgradeManager ให้ผู้เล่นเลือกการ์ดก่อน
# เลือกเสร็จ UpgradeManager เรียก resume_after_cards() แล้วค่อยนับถอยหลังไป Wave ถัดไป
#
# หน้า Game Over: ผู้เล่นตาย -> จดค่า Wave + เวลารอดชีวิต -> รอ game_over_delay วินาที -> แสดงหน้าตาย

signal wave_started(wave: int, total: int)
signal wave_cleared(wave: int)
signal enemies_changed(remaining: int, total: int)   # remaining = ที่เหลือในแมพ + ที่ยังไม่เกิด

const MELEE_SCENE := preload("res://scenes/enemy_melee.tscn")
const RANGED_SCENE := preload("res://scenes/enemy_ranged.tscn")
const AOE_SCENE := preload("res://scenes/enemy_aoe.tscn")
const WaveHudScript := preload("res://scripts/wave_hud.gd")
const PickupScript := preload("res://scripts/pickup.gd")
const UpgradeScript := preload("res://scripts/upgrade_manager.gd")
const PauseMenuScript := preload("res://scripts/pause_menu.gd")
const GameOverScript := preload("res://scripts/game_over.gd")
const MapScript := preload("res://scripts/map_builder.gd")
const IntroScript := preload("res://scripts/intro_cutscene.gd")

enum State { WAITING, ACTIVE, CLEARED, STOPPED }

@export_group("Flow")
@export var start_wave := 1               # เริ่มเกมที่ Wave นี้ (ตั้ง 5 ไว้ทดสอบบอส แล้วอย่าลืมตั้งกลับเป็น 1)
@export var play_intro := true            # true = เล่นคัทซีนกระสวยลงจอดก่อนเริ่ม (กดข้ามได้) ปิดไว้ตอนทดสอบได้
@export var first_wave_delay := 3.0       # รอก่อน Wave แรก (วินาที)
@export var intermission_time := 4.0      # พักระหว่าง Wave
@export var auto_continue := true         # false = รอให้สคริปต์อื่นเรียก start_next_wave()
@export var use_cards := true             # true = จบ Wave แล้วรอเลือกการ์ดก่อนนับถอยหลัง
@export var card_resume_delay := 3.0      # เลือกการ์ดเสร็จแล้วรออีกกี่วินาทีก่อน Wave ถัดไป
@export var game_over_delay := 1.2        # ตายแล้วรอกี่วินาทีก่อนขึ้นหน้า Game Over

@export_group("Count")
@export var start_count := 5              # มอนใน Wave 1
@export var count_per_wave := 1.5         # เพิ่มต่อ Wave (ทศนิยมได้ เช่น 1.5 = +3 ทุก 2 Wave)
@export var max_alive := 12               # มอนอยู่ในแมพพร้อมกันสูงสุด

@export_group("Boss")
@export var boss_every := 5               # บอสโผล่ทุก N Wave (5 / 10 / 15 ...) 0 = ปิดบอส
@export var boss_escort_ratio := 0.5      # Wave บอสมีลูกสมุนเท่าไรของ Wave ปกติ (0.5 = ครึ่งหนึ่ง)
@export var boss_hp_per_tier := 0.5       # บอสรอบถัดไปอึดขึ้น +50% ต่อรอบ (รอบ 2 = x1.5, รอบ 3 = x2.0)
@export var boss_drop_health := 2         # บอสตายดรอปชุดฮิลกี่อัน
@export var boss_drop_ammo := 3           # บอสตายดรอปกระสุนกี่อัน

@export_group("Spawn")
@export var spawn_interval := 0.6         # ห่างกันกี่วินาทีต่อตัว
@export var spawn_radius_min := 22.0      # เกิดห่างผู้เล่นอย่างน้อยเท่านี้
@export var spawn_radius_max := 34.0
@export var arena_half_size := 700.0      # ไม่ให้เกิดนอกพื้น (พื้นกว้าง 1500 = ครึ่งละ 750)

@export_group("Enemy mix")
@export var melee_weight := 5.0
@export var ranged_weight := 3.0
@export var aoe_weight := 2.0
@export var ranged_from_wave := 1         # เริ่มเกิดตั้งแต่ Wave นี้
@export var aoe_from_wave := 1

@export_group("Scaling")
# HP / Damage: 1 + scale * (wave-1)^power  (power < 1 = โตช้าลงเรื่อยๆ)
@export var hp_scale := 0.20
@export var hp_power := 0.85
@export var damage_scale := 0.12
@export var damage_power := 0.80
# Speed: โตเร็วช่วงแรกแล้วชนเพดาน  1 + bonus * (1 - e^(-(wave-1)/ramp))
@export var speed_max_bonus := 0.5        # เพดาน +50%
@export var speed_ramp := 12.0            # ยิ่งมากยิ่งโตช้า

@export_group("Drops")
@export var drop_chance := 0.35           # โอกาสดรอปเมื่อฆ่ามอน 1 ตัว (0-1)
@export var health_weight := 1.0          # น้ำหนักสุ่มว่าจะเป็นเลือด
@export var ammo_weight := 1.5            # น้ำหนักสุ่มว่าจะเป็นกระสุน
@export var health_amount := 25.0
@export var ammo_amount := 7
@export var smart_drops := true           # เลือดเหลือน้อย/กระสุนใกล้หมด = ดรอปของนั้นบ่อยขึ้น
@export var debug_keys := true            # กด I = เสกไอเทมทดสอบหน้าผู้เล่น (เฉพาะตอนรันจาก editor)

var wave := 0
var total := 0           # จำนวนมอนทั้งหมดของ Wave นี้
var spawned := 0
var state := State.WAITING
var countdown := 0.0     # วินาทีที่เหลือก่อน Wave ถัดไป (0 = ไม่ได้นับ)
var run_time := 0.0      # เวลาที่รอดชีวิตในรอบนี้ (วินาที) ไม่นับตอนเปิดเมนูหยุดเกม

var upgrades: UpgradeManager   # null ถ้าปิด use_cards หรือหาผู้เล่นไม่เจอ

var _alive: Array = []
var _spawn_timer := 0.0
var _player: Node3D
var _awaiting_cards := false
var _stats_timer := 0.0
var _pause_menu: Control
var _game_over: Control
var _map: MapBuilder   # แมพ Fallen Earth (ซาก/หิน/ต้นไม้ ฯลฯ) ไว้เช็คจุดเกิดมอน
var _hud: Control      # Wave HUD (ไว้ขึ้นป้ายเตรียมตัวหลังคัทซีนจบ)
var _intro_running := false   # true ระหว่างคัทซีน: Wave / นาฬิกาเวลาเล่นหยุดนิ่ง

func _ready() -> void:
	wave = maxi(start_wave, 1) - 1   # _begin_wave จะ +1 ให้เอง
	_find_player()
	_build_map()
	_build_hud()
	_build_upgrades()
	_build_pause_menu()
	_build_game_over()
	GameStats.start_run()
	countdown = first_wave_delay
	state = State.WAITING
	if play_intro and is_instance_valid(_player):
		_start_intro()

func _process(delta: float) -> void:
	if _intro_running:
		return   # คัทซีนกำลังเล่น: ยังไม่นับเวลา ไม่เริ่ม Wave
	# สถิติ: นับเวลาเล่นรวม (ตอนเกมหยุด _process ไม่ทำงาน จึงไม่นับเวลาที่เปิดเมนู) + เซฟทุก 20 วินาที
	if state != State.STOPPED:
		run_time += delta
		GameStats.add_play_time(delta)
		_stats_timer += delta
		if _stats_timer >= 20.0:
			_stats_timer = 0.0
			GameStats.save()

	match state:
		State.WAITING:
			countdown -= delta
			if countdown <= 0.0:
				countdown = 0.0
				_begin_wave()
		State.ACTIVE:
			_spawn_tick(delta)
		State.CLEARED:
			if auto_continue and not _awaiting_cards:
				countdown -= delta
				if countdown <= 0.0:
					countdown = 0.0
					start_next_wave()

# ---------------------------------------------------------------
# เรียกจากภายนอกได้
# ---------------------------------------------------------------
func start_next_wave() -> void:
	if state == State.CLEARED or state == State.WAITING:
		_begin_wave()

func remaining() -> int:
	return (total - spawned) + _alive.size()

# Wave นี้เป็น Wave บอสไหม (HUD ใช้)
func is_boss_wave(w: int) -> bool:
	return boss_every > 0 and w > 0 and w % boss_every == 0

# UpgradeManager เรียกหลังผู้เล่นเลือกการ์ดเสร็จ: เริ่มนับถอยหลังไป Wave ถัดไป
func resume_after_cards() -> void:
	if state != State.CLEARED:
		return
	_awaiting_cards = false
	countdown = card_resume_delay
	if not auto_continue:
		start_next_wave()

# ---------------------------------------------------------------
# สูตรความยาก
# ---------------------------------------------------------------
func count_for(w: int) -> int:
	return start_count + int(count_per_wave * float(w - 1))

func hp_mult(w: int) -> float:
	return 1.0 + hp_scale * pow(float(w - 1), hp_power)

func damage_mult(w: int) -> float:
	return 1.0 + damage_scale * pow(float(w - 1), damage_power)

func speed_mult(w: int) -> float:
	return 1.0 + speed_max_bonus * (1.0 - exp(-float(w - 1) / speed_ramp))

# ---------------------------------------------------------------
# Wave
# ---------------------------------------------------------------
func _begin_wave() -> void:
	wave += 1
	_awaiting_cards = false
	total = count_for(wave)
	if is_boss_wave(wave):
		total = int(float(total) * boss_escort_ratio) + 1   # ลูกสมุนครึ่งหนึ่ง + บอส 1 ตัว (ตัวแรกที่เกิด)
	spawned = 0
	_spawn_timer = 0.3
	state = State.ACTIVE
	GameStats.record_wave(wave)
	print("Wave %d: %d ตัว | HP x%.2f  DMG x%.2f  SPD x%.2f" % [
		wave, total, hp_mult(wave), damage_mult(wave), speed_mult(wave)])
	wave_started.emit(wave, total)
	enemies_changed.emit(remaining(), total)

func _finish_wave() -> void:
	state = State.CLEARED
	_awaiting_cards = use_cards and upgrades != null
	# รอการ์ดอยู่ = ไม่นับถอยหลัง (นับหลังเลือกเสร็จ ใน resume_after_cards)
	countdown = intermission_time if (auto_continue and not _awaiting_cards) else 0.0
	GameStats.save()
	wave_cleared.emit(wave)

func _spawn_tick(delta: float) -> void:
	if spawned >= total:
		return
	_spawn_timer -= delta
	if _spawn_timer <= 0.0 and _alive.size() < max_alive:
		_spawn_one()
		_spawn_timer = spawn_interval

func _spawn_one() -> void:
	var is_boss := is_boss_wave(wave) and spawned == 0   # Wave บอส: ตัวแรกที่เกิดคือบอส
	var e: EnemyBase
	if is_boss:
		e = EnemyBoss.new()
	else:
		e = _pick_scene().instantiate() as EnemyBase

	# _init ของมอนแต่ละแบบตั้งค่าพื้นฐานไว้แล้ว ตรงนี้คูณตาม Wave
	# (ปล่อย wave ในตัวมอนเป็น 1 จึงไม่ซ้อนกับสูตร growth เดิมใน enemy_base)
	e.max_hp *= hp_mult(wave)
	if is_boss:
		var tier := wave / boss_every   # บอสตัวที่เท่าไร (1, 2, 3 ...)
		e.max_hp *= 1.0 + boss_hp_per_tier * float(tier - 1)
	e.damage *= damage_mult(wave)
	e.move_speed *= speed_mult(wave)

	e.died.connect(_on_enemy_gone)
	e.died.connect(_on_enemy_died)
	e.tree_exited.connect(_on_enemy_gone.bind(e))

	get_tree().current_scene.add_child(e)
	e.global_position = _spawn_position(3.0 if is_boss else 1.2)

	_alive.append(e)
	spawned += 1
	enemies_changed.emit(remaining(), total)

func _on_enemy_gone(enemy: Node) -> void:
	var idx := _alive.find(enemy)
	if idx == -1:
		return
	_alive.remove_at(idx)
	if not is_inside_tree():
		return
	enemies_changed.emit(remaining(), total)
	if state == State.ACTIVE and spawned >= total and _alive.is_empty():
		_finish_wave()

# ---------------------------------------------------------------
# ดรอปของ
# ---------------------------------------------------------------
func _on_enemy_died(enemy: Node) -> void:
	GameStats.add_kill()
	var pos: Vector3 = enemy.global_position

	# บอสตาย: ดรอปแน่นอน ทั้งเลือดและกระสุน กระจายรอบจุดที่ตาย
	if enemy is EnemyBoss:
		for i in boss_drop_health + boss_drop_ammo:
			var k: int = PickupScript.Kind.HEALTH if i < boss_drop_health else PickupScript.Kind.AMMO
			var a := TAU * float(i) / float(boss_drop_health + boss_drop_ammo)
			drop_pickup(k, pos + Vector3(cos(a), 0.0, sin(a)) * 2.5)
		return

	if randf() > drop_chance:
		return

	var w_h := health_weight
	var w_a := ammo_weight
	if smart_drops and is_instance_valid(_player):
		var hp_ratio := float(_player.get("health")) / maxf(float(_player.get("max_health")), 1.0)
		if hp_ratio < 0.4:
			w_h *= 2.5
		elif hp_ratio >= 1.0:
			w_h *= 0.2
		var gun = _player.get("camera")
		if gun != null:
			if gun.mag + gun.reserve < gun.mag_size:
				w_a *= 2.5
			elif gun.reserve >= gun.max_reserve:
				w_a *= 0.2

	var kind: int = PickupScript.Kind.HEALTH
	if randf() * (w_h + w_a) >= w_h:
		kind = PickupScript.Kind.AMMO
	drop_pickup(kind, pos)

# วางไอเทมที่ตำแหน่งนี้ (kind = PickupScript.Kind.HEALTH / AMMO)
func drop_pickup(kind: int, pos: Vector3) -> void:
	var p = PickupScript.new()
	p.kind = kind
	p.amount = health_amount if kind == PickupScript.Kind.HEALTH else float(ammo_amount)
	get_tree().current_scene.add_child(p)
	p.global_position = Vector3(
		pos.x + randf_range(-0.5, 0.5), maxf(pos.y, 0.0), pos.z + randf_range(-0.5, 0.5))

func _unhandled_input(event: InputEvent) -> void:
	if not (debug_keys and OS.is_debug_build()):
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_I:
		if not is_instance_valid(_player):
			_find_player()
		if not is_instance_valid(_player):
			return
		var fwd := -_player.global_transform.basis.z
		var right := _player.global_transform.basis.x
		var base := _player.global_position + fwd * 6.0
		drop_pickup(PickupScript.Kind.HEALTH, base - right * 1.5)
		drop_pickup(PickupScript.Kind.AMMO, base + right * 1.5)

func _pick_scene() -> PackedScene:
	var w_m := melee_weight
	var w_r := ranged_weight if wave >= ranged_from_wave else 0.0
	var w_a := aoe_weight if wave >= aoe_from_wave else 0.0
	var roll := randf() * (w_m + w_r + w_a)
	if roll < w_m:
		return MELEE_SCENE
	roll -= w_m
	if roll < w_r:
		return RANGED_SCENE
	if w_a > 0.0:
		return AOE_SCENE
	return MELEE_SCENE

func _spawn_position(margin := 1.2) -> Vector3:
	if not is_instance_valid(_player):
		_find_player()
	var center := _player.global_position if is_instance_valid(_player) else Vector3.ZERO
	var p := center
	# สุ่มหลายครั้งจนได้จุดที่ไม่ทับซาก/หิน/ต้นไม้ (กันมอนเกิดติดในสิ่งกีดขวาง)
	for i in 12:
		var a := randf() * TAU
		var r := randf_range(spawn_radius_min, spawn_radius_max)
		p = center + Vector3(cos(a), 0.0, sin(a)) * r
		p.x = clampf(p.x, -arena_half_size, arena_half_size)
		p.z = clampf(p.z, -arena_half_size, arena_half_size)
		p.y = 0.05
		if _map == null or _map.is_free(p, margin):
			break
	return p

# ---------------------------------------------------------------
# ผู้เล่น / GUI
# ---------------------------------------------------------------
func _find_player() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null and get_parent() != null:
		_player = get_parent().find_child("Player", true, false) as Node3D
	if _player != null and _player.has_signal("died") and not _player.is_connected("died", _on_player_died):
		_player.connect("died", _on_player_died)

func _on_player_died() -> void:
	state = State.STOPPED
	countdown = 0.0
	GameStats.save()

	# ตายแล้วห้ามเปิดเมนูหยุดเกมทับหน้า Game Over
	if is_instance_valid(_pause_menu):
		_pause_menu.locked = true

	# จดค่าไว้ตอนตายเลย (ไม่รอหน่วงเวลา เพื่อให้ตรงกับจังหวะที่ตายจริง)
	var reached := wave
	var survived := run_time

	await get_tree().create_timer(game_over_delay).timeout   # ให้เห็นตัวละครล้มก่อนขึ้นหน้าตาย
	if not is_inside_tree():
		return
	if is_instance_valid(_game_over):
		_game_over.show_result(reached, survived)

# ---------------------------------------------------------------
# คัทซีนเปิดเกม (intro_cutscene.gd)
# ---------------------------------------------------------------
func _start_intro() -> void:
	_intro_running = true
	if is_instance_valid(_pause_menu):
		_pause_menu.locked = true   # ห้ามเปิดเมนูหยุดเกมระหว่างคัทซีน

	# กันพื้นที่ ไม่ให้ของตกแต่งแมพไปอยู่ใต้กระสวยและแนวกล้องคัทซีน (และมอนไม่เกิดทับ)
	if _map != null:
		_map.reserve(Vector2(0.0, 12.0), 11.0)
		_map.reserve(Vector2(-6.0, 26.0), 9.0)
		_map.reserve(Vector2(-12.0, 38.0), 8.0)

	var c = IntroScript.new()
	c.name = "IntroCutscene"
	add_child(c)
	c.finished.connect(_on_intro_finished)
	c.start(_player)

func _on_intro_finished() -> void:
	_intro_running = false
	if is_instance_valid(_pause_menu):
		_pause_menu.locked = false
	if is_instance_valid(_hud):
		_hud._show_banner(GameSettings.t("wave.get_ready"), "", Color(0.85, 0.85, 0.92))

# ปิดหน้าต่างเกมกลางคัน ก็เซฟสถิติไว้
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		GameStats.save()
		GameSettings.save()

func _build_map() -> void:
	_map = MapScript.new()
	_map.name = "MapBuilder"
	add_child(_map)

func _build_pause_menu() -> void:
	var layer := CanvasLayer.new()
	layer.name = "PauseLayer"
	layer.layer = 10   # อยู่เหนือทุก HUD และหน้าเลือกการ์ด
	_pause_menu = PauseMenuScript.new()
	_pause_menu.name = "PauseMenu"
	layer.add_child(_pause_menu)
	add_child(layer)

func _build_game_over() -> void:
	var layer := CanvasLayer.new()
	layer.name = "GameOverLayer"
	layer.layer = 11   # อยู่เหนือทุกอย่าง รวมถึงเมนูหยุดเกม
	_game_over = GameOverScript.new()
	_game_over.name = "GameOver"
	layer.add_child(_game_over)
	add_child(layer)

func _build_upgrades() -> void:
	if not use_cards or not is_instance_valid(_player):
		return
	upgrades = UpgradeScript.new()
	upgrades.name = "UpgradeManager"
	add_child(upgrades)
	upgrades.bind(self, _player)

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "WaveLayer"
	var hud = WaveHudScript.new()
	hud.name = "WaveHUD"
	layer.add_child(hud)
	add_child(layer)
	_hud = hud
	hud.bind(self)

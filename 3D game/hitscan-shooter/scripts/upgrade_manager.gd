class_name UpgradeManager
extends Node

# ระบบการ์ดความสามารถ: จบ Wave -> สุ่มการ์ด 3 ใบ -> ผู้เล่นเลือก 1 ใบ -> Wave ถัดไปเริ่มนับถอยหลัง
# - เลือกซ้ำ = สแตกทับ (stacks[id] เพิ่มขึ้น)
# - ค่าแบบคูณ (ดาเมจ, ความเร็ว ฯลฯ) คำนวณจากค่าตั้งต้น x จำนวนสแตก จึงไม่เพี้ยนสะสม
# - สร้าง UI ให้เองในโค้ด (WaveManager เรียก bind() ให้) ไม่ต้องลาก node
#
# อยากเพิ่มการ์ดใหม่: เพิ่มใน DEFS + case ใน _apply() + case ใน total_text()

signal upgrade_chosen(id: String, stacks: int)

const CardUiScript := preload("res://scripts/card_ui.gd")
const StatsHudScript := preload("res://scripts/stats_hud.gd")

# ค่าต่อ 1 สแตก (ปรับบาลานซ์ที่นี่)
const MAG_PER := 2              # กระสุนในแม็ก +2 ต่อสแตก
const DAMAGE_PER := 0.20        # ดาเมจ +20% ต่อสแตก
const SPEED_PER := 0.08         # วิ่ง/เดิน +8% ต่อสแตก
const HP_PER := 20.0            # MaxHP +20 ต่อสแตก (ได้เลือดเพิ่มทันที 20)
const DROP_PER := 0.08          # โอกาสดรอป +8 จุดเปอร์เซ็นต์ต่อสแตก
const DROP_CAP := 0.90
const BULLET_PER := 0.25        # ความเร็วกระสุน +25% ต่อสแตก
const RELOAD_PER := 0.20        # รีโหลดเร็วขึ้น +20% ต่อสแตก (เวลา = ตั้งต้น / (1 + 0.2 x สแตก))
const COOLDOWN_FACTOR := 0.88   # เวลารอระหว่างนัด x0.88 ต่อสแตก
const MIN_FIRE_RATE := 0.08
const MIN_RELOAD := 0.3

# big = ตัวเลขใหญ่กลางการ์ด, color = สีประจำการ์ด
# ชื่อ/คำอธิบายทุกภาษาอยู่ใน GameSettings.STRINGS (card.<id>.title / .short / .unit)
const DEFS := [
	{"id": "mag", "big": "+2", "color": Color(1.0, 0.8, 0.25)},
	{"id": "damage", "big": "+20%", "color": Color(1.0, 0.35, 0.3)},
	{"id": "speed", "big": "+8%", "color": Color(0.4, 0.85, 1.0)},
	{"id": "hp", "big": "+20", "color": Color(0.95, 0.3, 0.45)},
	{"id": "drop", "big": "+8%", "color": Color(0.5, 1.0, 0.55)},
	{"id": "bullet", "big": "+25%", "color": Color(1.0, 0.6, 0.2)},
	{"id": "reload", "big": "+20%", "color": Color(0.75, 0.55, 1.0)},
	{"id": "cooldown", "big": "-12%", "color": Color(0.95, 0.9, 0.5)},
]

@export var show_delay := 1.2          # รอให้ป้าย WAVE CLEARED ขึ้นก่อนค่อยโชว์การ์ด
@export var cards_per_pick := 3

var stacks := {}   # id -> จำนวนสแตก (เรียงตามลำดับที่เลือกครั้งแรก)

var _wm: Node
var _player: Node
var _gun: Node
var _card_ui: Control

var _base_damage := 0.0
var _base_bullet_speed := 0.0
var _base_reload := 0.0
var _base_fire_rate := 0.0
var _base_drop := 0.0

func bind(wm: Node, player: Node) -> void:
	_wm = wm
	_player = player
	_gun = player.get("camera") if player != null else null

	if _gun != null:
		_base_damage = _gun.damage
		_base_bullet_speed = _gun.bullet_speed
		_base_reload = _gun.reload_time
		_base_fire_rate = _gun.fire_rate
	_base_drop = wm.drop_chance

	# การ์ดอยู่ layer บนสุด
	var card_layer := CanvasLayer.new()
	card_layer.name = "CardLayer"
	card_layer.layer = 5
	_card_ui = CardUiScript.new()
	_card_ui.name = "CardUI"
	card_layer.add_child(_card_ui)
	add_child(card_layer)
	_card_ui.picked.connect(_on_picked)
	_card_ui.closed.connect(_on_cards_closed)

	# HUD สแตกซ้ายล่าง
	var stats_layer := CanvasLayer.new()
	stats_layer.name = "StatsLayer"
	var stats := StatsHudScript.new()
	stats.name = "StatsHUD"
	stats_layer.add_child(stats)
	add_child(stats_layer)
	stats.bind(self)

	wm.wave_cleared.connect(_on_wave_cleared)

# ---------------------------------------------------------------
# ข้อมูลการ์ด (UI ใช้)
# ---------------------------------------------------------------
func def_of(id: String) -> Dictionary:
	for d in DEFS:
		if d.id == id:
			return d
	return {}

# ข้อความรวมของสแตกทั้งหมด เช่น "+40%"
func total_text(id: String, n: int) -> String:
	match id:
		"mag": return "+%d" % (MAG_PER * n)
		"damage": return "+%d%%" % roundi(DAMAGE_PER * n * 100.0)
		"speed": return "+%d%%" % roundi(SPEED_PER * n * 100.0)
		"hp": return "+%d" % roundi(HP_PER * n)
		"drop": return "+%d%%" % roundi(DROP_PER * n * 100.0)
		"bullet": return "+%d%%" % roundi(BULLET_PER * n * 100.0)
		"reload": return "+%d%%" % roundi(RELOAD_PER * n * 100.0)
		"cooldown": return "-%d%%" % roundi((1.0 - pow(COOLDOWN_FACTOR, n)) * 100.0)
	return ""

# ---------------------------------------------------------------
# Flow
# ---------------------------------------------------------------
func _on_wave_cleared(_wave: int) -> void:
	await get_tree().create_timer(show_delay, false).timeout   # false = หยุดตามตอนพักเกม
	if not is_inside_tree() or bool(_player.get("is_dead")):
		return

	var pool: Array = DEFS.duplicate()
	pool.shuffle()
	var options: Array = []
	for i in mini(cards_per_pick, pool.size()):
		var d: Dictionary = pool[i]
		var o := d.duplicate()
		o["owned"] = int(stacks.get(d.id, 0))
		options.append(o)
	_card_ui.open(options)

func _on_picked(id: String) -> void:
	stacks[id] = int(stacks.get(id, 0)) + 1
	_apply(id)
	upgrade_chosen.emit(id, stacks[id])

# ย่อการ์ดเสร็จแล้ว -> ปล่อยให้ Wave ถัดไปเริ่มนับถอยหลัง
func _on_cards_closed() -> void:
	if is_instance_valid(_wm):
		_wm.resume_after_cards()

# ---------------------------------------------------------------
# ใช้ผลของการ์ด
# ---------------------------------------------------------------
func _apply(id: String) -> void:
	var n: int = stacks[id]
	match id:
		"mag":
			if _gun != null:
				_gun.mag_size += MAG_PER
				_gun.mag += MAG_PER   # แถมกระสุนเต็มช่องที่เพิ่มมา
				_gun.emit_state()
		"damage":
			if _gun != null:
				_gun.damage = _base_damage * (1.0 + DAMAGE_PER * n)
		"speed":
			_player.speed_mult = 1.0 + SPEED_PER * n
		"hp":
			_player.max_health += HP_PER
			_player.health += HP_PER
			_player.health_changed.emit(_player.health, _player.max_health, HP_PER)
		"drop":
			_wm.drop_chance = minf(_base_drop + DROP_PER * n, DROP_CAP)
		"bullet":
			if _gun != null:
				_gun.bullet_speed = _base_bullet_speed * (1.0 + BULLET_PER * n)
		"reload":
			if _gun != null:
				_gun.reload_time = maxf(_base_reload / (1.0 + RELOAD_PER * n), MIN_RELOAD)
		"cooldown":
			if _gun != null:
				_gun.fire_rate = maxf(_base_fire_rate * pow(COOLDOWN_FACTOR, n), MIN_FIRE_RATE)

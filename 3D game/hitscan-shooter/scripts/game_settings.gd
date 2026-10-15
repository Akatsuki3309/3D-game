class_name GameSettings
extends RefCounted

# ศูนย์รวมการตั้งค่าของเกม (ภาษา, ความสว่าง, ระดับเสียง) + ตารางข้อความสองภาษา
# - เรียกใช้ได้จากทุกสคริปต์ผ่านชื่อคลาส ไม่ต้องใส่ Autoload:
#       GameSettings.t("wave.cleared")          -> ข้อความตามภาษาปัจจุบัน
#       GameSettings.t("wave.n") % wave         -> ใช้กับข้อความที่มี %d ได้
# - HUD ที่วาดใหม่ทุกเฟรมจะเปลี่ยนภาษาให้เองทันทีที่ผู้เล่นเลือกภาษาใหม่
# - บันทึกลง user://settings.cfg (โหลดอัตโนมัติตอนเรียกใช้ครั้งแรก)
# - สร้างบัส Music / SFX ให้เอง ตอนมีเสียงจริง ให้ตั้ง AudioStreamPlayer.bus = "Music" หรือ "SFX"
#
# เพิ่มข้อความใหม่: เพิ่ม key ใน STRINGS ทั้ง "en" และ "th"

const PATH := "user://settings.cfg"

const STRINGS := {
	# --- Wave HUD ---
	"wave.word": {"en": "WAVE", "th": "เวฟ"},
	"wave.enemies_left": {"en": "ENEMIES LEFT", "th": "ศัตรูที่เหลือ"},
	"wave.starting_in": {"en": "STARTING IN %d", "th": "เริ่มใน %d"},
	"wave.next_in": {"en": "NEXT WAVE IN %d", "th": "เวฟถัดไปใน %d"},
	"wave.get_ready": {"en": "GET READY", "th": "เตรียมตัว"},
	"wave.n": {"en": "WAVE %d", "th": "เวฟ %d"},
	"wave.n_enemies": {"en": "%d ENEMIES", "th": "ศัตรู %d ตัว"},
	"wave.cleared": {"en": "WAVE CLEARED", "th": "เคลียร์เวฟ!"},
	"wave.boss": {"en": "BOSS WAVE", "th": "เวฟบอส"},
	"intro.skip": {"en": "PRESS ANY KEY TO SKIP", "th": "กดปุ่มใดก็ได้เพื่อข้าม"},
	"boss.name": {"en": "ALIEN WARLORD", "th": "จอมทัพเอเลี่ยน"},
	"boss.enraged": {"en": "ENRAGED", "th": "คลุ้มคลั่ง"},

	# --- Ammo HUD ---
	"ammo.reloading": {"en": "RELOADING", "th": "กำลังรีโหลด"},
	"ammo.press_r": {"en": "PRESS R TO RELOAD", "th": "กด R เพื่อรีโหลด"},
	"ammo.none": {"en": "NO AMMO", "th": "กระสุนหมด"},

	# --- Pickup ---
	"pickup.health": {"en": "HEALTH PACK", "th": "ชุดฮิล"},
	"pickup.ammo": {"en": "AMMO", "th": "กระสุน"},
	"pickup.hp_plus": {"en": "+%d HP", "th": "+%d HP"},
	"pickup.ammo_plus": {"en": "+%d AMMO", "th": "+%d กระสุน"},
	"pickup.hp_full": {"en": "HP FULL", "th": "เลือดเต็ม"},
	"pickup.ammo_full": {"en": "AMMO FULL", "th": "กระสุนเต็ม"},

	# --- การ์ดความสามารถ ---
	"card.choose": {"en": "CHOOSE AN UPGRADE", "th": "เลือกความสามารถ"},
	"card.hint": {"en": "click a card or press 1 / 2 / 3", "th": "คลิกการ์ดหรือกด 1 / 2 / 3"},
	"card.new": {"en": "NEW", "th": "ใหม่"},
	"card.owned": {"en": "OWNED x%d  >  x%d", "th": "มีอยู่ x%d  >  x%d"},
	"stats.title": {"en": "UPGRADES", "th": "ความสามารถ"},

	"card.mag.title": {"en": "EXTENDED MAG", "th": "แม็กขยาย"},
	"card.mag.short": {"en": "Mag Size", "th": "จุแม็ก"},
	"card.mag.unit": {"en": "MAG SIZE", "th": "กระสุนในแม็ก"},
	"card.damage.title": {"en": "HEAVY ROUNDS", "th": "กระสุนหนัก"},
	"card.damage.short": {"en": "Damage", "th": "ดาเมจ"},
	"card.damage.unit": {"en": "BULLET DAMAGE", "th": "ดาเมจกระสุน"},
	"card.speed.title": {"en": "LIGHT FEET", "th": "ฝีเท้าเบา"},
	"card.speed.short": {"en": "Move Speed", "th": "ความเร็วเดิน"},
	"card.speed.unit": {"en": "MOVE SPEED", "th": "ความเร็วเคลื่อนที่"},
	"card.hp.title": {"en": "TOUGH SKIN", "th": "ผิวหนา"},
	"card.hp.short": {"en": "Max HP", "th": "เลือดสูงสุด"},
	"card.hp.unit": {"en": "MAX HP", "th": "เลือดสูงสุด"},
	"card.drop.title": {"en": "SCAVENGER", "th": "นักเก็บของ"},
	"card.drop.short": {"en": "Drop Rate", "th": "อัตราดรอป"},
	"card.drop.unit": {"en": "DROP RATE", "th": "อัตราดรอป"},
	"card.bullet.title": {"en": "HOT LOAD", "th": "ดินร้อนแรง"},
	"card.bullet.short": {"en": "Bullet Speed", "th": "ความเร็วกระสุน"},
	"card.bullet.unit": {"en": "BULLET SPEED", "th": "ความเร็วกระสุน"},
	"card.reload.title": {"en": "QUICK HANDS", "th": "มือไว"},
	"card.reload.short": {"en": "Reload Speed", "th": "รีโหลดเร็ว"},
	"card.reload.unit": {"en": "RELOAD SPEED", "th": "ความเร็วรีโหลด"},
	"card.cooldown.title": {"en": "TRIGGER HAPPY", "th": "นิ้วไว"},
	"card.cooldown.short": {"en": "Fire Delay", "th": "หน่วงการยิง"},
	"card.cooldown.unit": {"en": "FIRE DELAY", "th": "เวลารอระหว่างนัด"},

	# --- เมนูหยุดเกม ---
	"pause.title": {"en": "PAUSED", "th": "หยุดเกม"},
	"pause.resume": {"en": "RESUME", "th": "เล่นต่อ"},
	"pause.settings": {"en": "SETTINGS", "th": "ตั้งค่า"},
	"pause.main_menu": {"en": "MAIN MENU", "th": "กลับเมนูหลัก"},
	"pause.quit": {"en": "QUIT GAME", "th": "ออกจากเกม"},
	"pause.no_menu": {"en": "Main menu isn't available yet", "th": "ยังไม่มีหน้าเมนูหลัก"},

	# --- หน้าจอตาย (Game Over) ---
	"over.title": {"en": "YOU DIED", "th": "คุณตายแล้ว"},
	"over.wave": {"en": "Wave Reached", "th": "Wave ที่ไปถึง"},
	"over.time": {"en": "Survival Time", "th": "เวลาที่รอดชีวิต"},
	"over.menu": {"en": "MAIN MENU", "th": "กลับเมนูหลัก"},

	# --- เมนูหลัก / สถิติ ---
	"menu.title": {"en": "FALLEN EARTH", "th": "FALLEN EARTH"},
	"menu.tagline": {"en": "SURVIVE THE ENDLESS WAVES", "th": "เอาชีวิตรอดจากเวฟที่ไม่มีวันจบ"},
	"menu.start": {"en": "START GAME", "th": "เริ่มเกม"},
	"menu.settings": {"en": "SETTINGS", "th": "ตั้งค่า"},
	"menu.stats": {"en": "STATISTICS", "th": "สถิติ"},
	"menu.quit": {"en": "QUIT GAME", "th": "ออกจากเกม"},
	"stats.page_title": {"en": "STATISTICS", "th": "สถิติ"},
	"stats.kills": {"en": "Total Enemies Killed", "th": "ฆ่ามอนรวมทั้งหมด"},
	"stats.playtime": {"en": "Total Play Time", "th": "เวลาเล่นรวม"},
	"stats.best_wave": {"en": "Highest Wave", "th": "Wave สูงสุด"},
	"stats.best_run": {"en": "Most Kills in One Run", "th": "ฆ่าได้มากสุดในรอบเดียว"},
	"stats.games": {"en": "Games Played", "th": "จำนวนรอบที่เล่น"},
	"stats.time_hms": {"en": "%dh %dm %ds", "th": "%d ชม. %d นาที %d วิ"},
	"stats.time_ms": {"en": "%dm %ds", "th": "%d นาที %d วิ"},

	# --- ตั้งค่า ---
	"set.title": {"en": "SETTINGS", "th": "ตั้งค่า"},
	"set.back": {"en": "BACK", "th": "กลับ"},
	"tab.language": {"en": "LANGUAGE", "th": "ภาษา"},
	"tab.display": {"en": "DISPLAY", "th": "หน้าจอ"},
	"tab.audio": {"en": "AUDIO", "th": "เสียง"},
	"tab.controls": {"en": "CONTROLS", "th": "ปุ่มควบคุม"},
	"lang.choose": {"en": "Choose the game language", "th": "เลือกภาษาของเกม"},
	"disp.brightness": {"en": "Brightness", "th": "ความสว่างจอ"},
	"aud.master": {"en": "Master Volume", "th": "เสียงหลัก"},
	"aud.music": {"en": "Music", "th": "เสียงเพลง"},
	"aud.sfx": {"en": "Sound Effects", "th": "เสียงเอฟเฟกต์"},

	# --- รายการปุ่ม ---
	"ctl.forward": {"en": "Move Forward", "th": "เดินหน้า"},
	"ctl.back": {"en": "Move Back", "th": "ถอยหลัง"},
	"ctl.left": {"en": "Move Left", "th": "เดินซ้าย"},
	"ctl.right": {"en": "Move Right", "th": "เดินขวา"},
	"ctl.jump": {"en": "Jump", "th": "กระโดด"},
	"ctl.sprint": {"en": "Sprint", "th": "วิ่ง"},
	"ctl.crouch": {"en": "Crouch / Slide", "th": "ย่อ / สไลด์"},
	"ctl.shoot": {"en": "Shoot", "th": "ยิง"},
	"ctl.reload": {"en": "Reload", "th": "รีโหลด"},
	"ctl.card": {"en": "Choose Upgrade Card", "th": "เลือกการ์ด"},
	"ctl.pause": {"en": "Pause", "th": "หยุดเกม"},
	"key.lmb": {"en": "Left Mouse", "th": "คลิกซ้าย"},
	"key.rmb": {"en": "Right Mouse", "th": "คลิกขวา"},
	"key.mmb": {"en": "Middle Mouse", "th": "คลิกกลาง"},
}

const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"

# ค่าเหล่านี้อ่านได้จากทุกที่ (ปรับผ่านเมนูตั้งค่า)
static var language := "en"           # "en" / "th"
static var brightness := 1.0          # 0.5 - 1.5
static var vol_master := 1.0          # 0 - 1
static var vol_music := 1.0
static var vol_sfx := 1.0

static var _loaded := false

# ---------------------------------------------------------------
# ข้อความ
# ---------------------------------------------------------------
static func t(key: String) -> String:
	ensure_loaded()
	var entry = STRINGS.get(key)
	if entry == null:
		return key   # ลืมใส่ใน STRINGS = เห็น key ตรงๆ จะได้รู้
	return entry.get(language, entry["en"])

# ---------------------------------------------------------------
# โหลด / บันทึก
# ---------------------------------------------------------------
static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true

	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		language = str(cfg.get_value("general", "language", "en"))
		brightness = clampf(float(cfg.get_value("display", "brightness", 1.0)), 0.5, 1.5)
		vol_master = clampf(float(cfg.get_value("audio", "master", 1.0)), 0.0, 1.0)
		vol_music = clampf(float(cfg.get_value("audio", "music", 1.0)), 0.0, 1.0)
		vol_sfx = clampf(float(cfg.get_value("audio", "sfx", 1.0)), 0.0, 1.0)
	if not (language == "en" or language == "th"):
		language = "en"

	_ensure_bus(BUS_MUSIC)
	_ensure_bus(BUS_SFX)
	apply_audio()

static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("general", "language", language)
	cfg.set_value("display", "brightness", brightness)
	cfg.set_value("audio", "master", vol_master)
	cfg.set_value("audio", "music", vol_music)
	cfg.set_value("audio", "sfx", vol_sfx)
	cfg.save(PATH)

# ---------------------------------------------------------------
# เสียง
# ---------------------------------------------------------------
static func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")

static func _set_bus(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_mute(idx, linear <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.001)))

static func apply_audio() -> void:
	_set_bus("Master", vol_master)
	_set_bus(BUS_MUSIC, vol_music)
	_set_bus(BUS_SFX, vol_sfx)

# ---------------------------------------------------------------
# ความสว่าง (ใช้ Environment ของ WorldEnvironment ในฉาก ถ้าไม่มีจะสร้างให้)
# ---------------------------------------------------------------
static func apply_brightness(tree: SceneTree) -> void:
	var scene := tree.current_scene
	if scene == null:
		return

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
	we.environment.adjustment_enabled = true
	we.environment.adjustment_brightness = brightness

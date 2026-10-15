class_name GameStats
extends RefCounted

# สถิติตลอดการเล่น (เก็บข้ามรอบ บันทึกลง user://stats.cfg)
# - เรียกใช้ผ่านชื่อคลาสได้ทุกที่ ไม่ต้อง Autoload: GameStats.add_kill()
# - WaveManager เป็นคนเรียกเก็บค่าตอนเล่น (นับมอน, Wave สูงสุด, เวลาเล่น)
# - หน้าเมนูหลัก (main_menu.gd) อ่านค่ามาแสดง

const PATH := "user://stats.cfg"

static var total_kills := 0
static var total_play_time := 0.0   # วินาที
static var best_wave := 0
static var games_played := 0
static var best_run_kills := 0      # ฆ่าได้มากสุดในรอบเดียว

static var run_kills := 0           # ของรอบปัจจุบัน (ไม่บันทึก)

static var _loaded := false

static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	total_kills = int(cfg.get_value("stats", "total_kills", 0))
	total_play_time = float(cfg.get_value("stats", "total_play_time", 0.0))
	best_wave = int(cfg.get_value("stats", "best_wave", 0))
	games_played = int(cfg.get_value("stats", "games_played", 0))
	best_run_kills = int(cfg.get_value("stats", "best_run_kills", 0))

static func save() -> void:
	ensure_loaded()
	var cfg := ConfigFile.new()
	cfg.set_value("stats", "total_kills", total_kills)
	cfg.set_value("stats", "total_play_time", total_play_time)
	cfg.set_value("stats", "best_wave", best_wave)
	cfg.set_value("stats", "games_played", games_played)
	cfg.set_value("stats", "best_run_kills", best_run_kills)
	cfg.save(PATH)

# เริ่มรอบใหม่ (WaveManager เรียกตอนเข้าฉากเกม)
static func start_run() -> void:
	ensure_loaded()
	games_played += 1
	run_kills = 0
	save()

static func add_kill() -> void:
	ensure_loaded()
	total_kills += 1
	run_kills += 1
	best_run_kills = maxi(best_run_kills, run_kills)

static func record_wave(wave: int) -> void:
	ensure_loaded()
	best_wave = maxi(best_wave, wave)

static func add_play_time(delta: float) -> void:
	ensure_loaded()
	total_play_time += delta

# รีเซ็ตสถิติทั้งหมด (ยังไม่มีปุ่มในเมนู ไว้เรียกเองถ้าต้องการ)
static func reset_all() -> void:
	total_kills = 0
	total_play_time = 0.0
	best_wave = 0
	games_played = 0
	best_run_kills = 0
	run_kills = 0
	_loaded = true
	save()

extends Control

# GUI ของระบบ Wave วาดด้วยโค้ดล้วน สไตล์เดียวกับหลอดเลือดและกระสุน
# - กลางบน: เลข Wave ตัวใหญ่ เด้งตอนขึ้น Wave ใหม่ + นับถอยหลังก่อน Wave ถัดไป
# - ขวาบน: จำนวนมอนที่เหลือ / ทั้งหมด + แถบความคืบหน้า
# - กลางจอ: ป้าย "WAVE N" ตอนเริ่ม และ "WAVE CLEARED" ตอนเคลียร์

@export var margin := Vector2(28, 22)
@export var banner_duration := 2.4

const PAD := 18.0
const WAVE_PANEL := Vector2(220, 92)
const COUNT_PANEL := Vector2(210, 86)

var _wm: Node
var _wave := 0
var _remaining := 0
var _total := 1

var _wave_pop := 0.0     # เลข Wave เด้งตอนขึ้นรอบใหม่
var _count_pop := 0.0    # เลขมอนเด้งตอนฆ่าได้
var _bar := 0.0          # แถบความคืบหน้า (ไหลนุ่มๆ)

var _is_boss_wave := false
var _boss_alpha := 0.0     # แถบเลือดบอสค่อยๆ โผล่ / จางหาย
var _boss_fill := 1.0
var _boss_ghost := 1.0     # แถบขาวหน่วงตามหลัง
var _boss_enraged := false

var _banner_main := ""
var _banner_sub := ""
var _banner_color := Color.WHITE
var _banner_left := 0.0

var _style := StyleBoxFlat.new()
var _frame := StyleBoxFlat.new()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)

	_style.anti_aliasing = true

	_frame.anti_aliasing = true
	_frame.bg_color = Color(0.07, 0.07, 0.09, 0.88)
	_frame.set_border_width_all(2)
	_frame.border_color = Color(1, 1, 1, 0.22)
	_frame.shadow_color = Color(0, 0, 0, 0.45)
	_frame.shadow_size = 6
	_frame.shadow_offset = Vector2(0, 2)
	_frame.set_corner_radius_all(14)

# WaveManager เรียกหลังสร้างเสร็จ
func bind(wm: Node) -> void:
	_wm = wm
	wm.wave_started.connect(_on_wave_started)
	wm.wave_cleared.connect(_on_wave_cleared)
	wm.enemies_changed.connect(_on_enemies_changed)
	_show_banner(GameSettings.t("wave.get_ready"), "", Color(0.85, 0.85, 0.92))

func _on_wave_started(wave: int, total: int) -> void:
	_wave = wave
	_total = maxi(total, 1)
	_remaining = total
	_bar = 0.0
	_wave_pop = 1.0
	_is_boss_wave = wm_is_boss(wave)
	if _is_boss_wave:
		_boss_fill = 1.0
		_boss_ghost = 1.0
		_boss_enraged = false
		_show_banner(GameSettings.t("wave.boss"), GameSettings.t("wave.n") % wave, Color(1.0, 0.25, 0.2))
	else:
		_show_banner(GameSettings.t("wave.n") % wave, GameSettings.t("wave.n_enemies") % total, Color(1.0, 0.82, 0.3))

func wm_is_boss(wave: int) -> bool:
	return _wm != null and _wm.has_method("is_boss_wave") and _wm.is_boss_wave(wave)

func _on_wave_cleared(_wave_num: int) -> void:
	_show_banner(GameSettings.t("wave.cleared"), "", Color(0.45, 1.0, 0.55))

func _on_enemies_changed(remaining: int, total: int) -> void:
	if remaining < _remaining:
		_count_pop = 1.0
	_remaining = remaining
	_total = maxi(total, 1)

func _show_banner(main: String, sub: String, color: Color) -> void:
	_banner_main = main
	_banner_sub = sub
	_banner_color = color
	_banner_left = banner_duration

func _process(delta: float) -> void:
	_wave_pop = move_toward(_wave_pop, 0.0, delta * 2.2)
	_count_pop = move_toward(_count_pop, 0.0, delta * 6.0)
	_banner_left = maxf(_banner_left - delta, 0.0)
	var target := 1.0 - float(_remaining) / float(_total) if _wave > 0 else 0.0
	_bar = move_toward(_bar, target, delta * 1.5)

	# แถบเลือดบอส: หาบอสที่ยังมีชีวิตอยู่
	var boss: Node = get_tree().get_first_node_in_group("boss")
	if boss != null and float(boss.get("hp")) > 0.0:
		var ratio := clampf(float(boss.get("hp")) / maxf(float(boss.get("hp_max")), 1.0), 0.0, 1.0)
		_boss_fill = ratio
		_boss_enraged = bool(boss.get("enraged"))
		_boss_alpha = move_toward(_boss_alpha, 1.0, delta * 3.0)
		_boss_ghost = maxf(_boss_ghost, ratio)
	else:
		_boss_alpha = move_toward(_boss_alpha, 0.0, delta * 2.0)
		_boss_fill = 0.0
	_boss_ghost = move_toward(_boss_ghost, _boss_fill, delta * 0.35)
	queue_redraw()

# ---------------------------------------------------------------
# วาด
# ---------------------------------------------------------------
func _draw() -> void:
	_draw_wave_panel()
	_draw_count_panel()
	_draw_boss_bar()
	_draw_banner()

func _draw_wave_panel() -> void:
	var center := Vector2(size.x * 0.5, margin.y + WAVE_PANEL.y * 0.5)
	var s := 1.0 + _wave_pop * 0.3
	draw_set_transform(center, 0.0, Vector2(s, s))

	draw_style_box(_frame, Rect2(-WAVE_PANEL * 0.5, WAVE_PANEL))
	_text_c(GameSettings.t("wave.word"), 0.0, -WAVE_PANEL.y * 0.5 + 28.0, 15, Color(0.72, 0.72, 0.8), 3)
	var pop_color := Color(1.0, 0.3, 0.25) if _is_boss_wave else Color(1.0, 0.82, 0.3)
	var num_color := (Color(1.0, 0.55, 0.5) if _is_boss_wave else Color.WHITE).lerp(pop_color, _wave_pop)
	_text_c(str(maxi(_wave, 1)), 0.0, 36.0, 54, num_color, 6)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# นับถอยหลังใต้ป้าย Wave
	if _wm != null and _wm.countdown > 0.0:
		var label: String = GameSettings.t("wave.starting_in") % ceili(_wm.countdown) if _wm.wave == 0 \
			else GameSettings.t("wave.next_in") % ceili(_wm.countdown)
		_text_c(label, size.x * 0.5, margin.y + WAVE_PANEL.y + 28.0, 18, Color(0.9, 0.9, 0.95), 4)

func _draw_count_panel() -> void:
	var font := ThemeDB.fallback_font
	var r := Rect2(Vector2(size.x - margin.x - COUNT_PANEL.x, margin.y), COUNT_PANEL)
	draw_style_box(_frame, r)

	draw_string(font, Vector2(r.position.x + PAD, r.position.y + 26.0), GameSettings.t("wave.enemies_left"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.72, 0.72, 0.8))

	# เลขที่เหลือ (เด้งตอนฆ่า, ส้มตอนใกล้หมด)
	var color := Color.WHITE
	if _remaining > 0 and _remaining <= 3 and _wave > 0:
		color = Color(1.0, 0.65, 0.2)
	color = color.lerp(Color(1.0, 0.9, 0.4), _count_pop)
	var txt := str(_remaining)
	var fs := int(40 + _count_pop * 6.0)
	var base := Vector2(r.position.x + PAD, r.position.y + 62.0)
	draw_string_outline(font, base, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, 0.85))
	draw_string(font, base, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)

	var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	draw_string(font, Vector2(base.x + w + 8.0, base.y), "/ %d" % _total,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.7, 0.7, 0.76))

	# แถบความคืบหน้า (เคลียร์ไปแล้วกี่ %)
	var inner_w := COUNT_PANEL.x - PAD * 2.0
	var bar_pos := Vector2(r.position.x + PAD, r.position.y + COUNT_PANEL.y - 18.0)
	_draw_pill(Rect2(bar_pos, Vector2(inner_w, 8.0)), Color(0.15, 0.15, 0.18))
	_draw_pill(Rect2(bar_pos, Vector2(inner_w * _bar, 8.0)), Color.from_hsv(0.08 + _bar * 0.25, 0.7, 0.95))

func _draw_boss_bar() -> void:
	if _boss_alpha <= 0.01:
		return
	var a := _boss_alpha
	var font := ThemeDB.fallback_font
	var w := 560.0
	var h := 58.0
	var r := Rect2(Vector2((size.x - w) * 0.5, margin.y + WAVE_PANEL.y + 52.0), Vector2(w, h))

	_frame.bg_color.a = 0.88 * a
	_frame.border_color = Color(1.0, 0.3, 0.25, 0.7 * a) if _boss_enraged else Color(1, 1, 1, 0.22 * a)
	draw_style_box(_frame, r)
	_frame.bg_color.a = 0.88
	_frame.border_color = Color(1, 1, 1, 0.22)

	# ชื่อ + ป้ายคลั่ง
	var name_txt := GameSettings.t("boss.name")
	var name_col := Color(1.0, 0.45, 0.35, a) if _boss_enraged else Color(0.9, 0.9, 0.95, a)
	draw_string_outline(font, Vector2(r.position.x + PAD, r.position.y + 22.0), name_txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color(0, 0, 0, 0.85 * a))
	draw_string(font, Vector2(r.position.x + PAD, r.position.y + 22.0), name_txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, name_col)
	if _boss_enraged:
		var blink := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 1000.0 * 8.0)
		draw_string(font, Vector2(r.position.x + PAD, r.position.y + 22.0), GameSettings.t("boss.enraged"),
			HORIZONTAL_ALIGNMENT_RIGHT, w - PAD * 2.0, 14, Color(1.0, 0.3, 0.2, a * blink))

	# หลอดเลือด (แถบขาวหน่วงตามหลัง)
	var bar := Rect2(r.position.x + PAD, r.position.y + 34.0, w - PAD * 2.0, 12.0)
	_draw_pill(bar, Color(0.15, 0.15, 0.18, a))
	_draw_pill(Rect2(bar.position, Vector2(bar.size.x * _boss_ghost, bar.size.y)), Color(1, 1, 1, 0.5 * a))
	var fill_col := Color(1.0, 0.15, 0.12, a) if _boss_enraged else Color(0.95, 0.5, 0.15, a)
	_draw_pill(Rect2(bar.position, Vector2(bar.size.x * _boss_fill, bar.size.y)), fill_col)

	# ขีดบอกจุดที่บอสจะคลั่ง (50%)
	if not _boss_enraged:
		var mx := bar.position.x + bar.size.x * 0.5
		draw_line(Vector2(mx, bar.position.y - 2.0), Vector2(mx, bar.end.y + 2.0), Color(1, 1, 1, 0.6 * a), 2.0)

func _draw_banner() -> void:
	if _banner_left <= 0.0:
		return
	var elapsed := banner_duration - _banner_left
	var alpha := clampf(minf(elapsed / 0.2, _banner_left / 0.6), 0.0, 1.0)
	var s := 1.0 + (1.0 - clampf(elapsed / 0.25, 0.0, 1.0)) * 0.4

	var center := Vector2(size.x * 0.5, size.y * 0.30)
	draw_set_transform(center, 0.0, Vector2(s, s))

	var main_color := Color(_banner_color, alpha)
	_text_c(_banner_main, 0.0, 0.0, 72, main_color, 8, alpha)
	if _banner_sub != "":
		_text_c(_banner_sub, 0.0, 40.0, 24, Color(1, 1, 1, alpha * 0.9), 5, alpha)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ---------------------------------------------------------------
# ตัวช่วยวาด
# ---------------------------------------------------------------
func _text_c(text: String, cx: float, y: float, font_size: int, color: Color, outline: int = 5, alpha: float = 1.0) -> void:
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var pos := Vector2(cx - w * 0.5, y)
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline, Color(0, 0, 0, 0.85 * alpha))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _draw_pill(r: Rect2, color: Color) -> void:
	if r.size.x < 1.0:
		return
	_style.bg_color = color
	_style.set_corner_radius_all(int(minf(r.size.x, r.size.y) * 0.5))
	draw_style_box(_style, r)

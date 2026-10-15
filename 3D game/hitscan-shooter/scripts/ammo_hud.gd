extends Control

# GUI กระสุนมุมขวาล่าง วาดด้วยโค้ดล้วน สไตล์เดียวกับหลอดเลือด
# - เลขกระสุนในแม็กตัวใหญ่ + กระสุนสำรองตัวเล็ก
# - แถวหัวกระสุน (ถ้าแม็กไม่เกิน 20 นัด) นัดที่ใช้แล้วจะมืดลง
# - ตัวเลขเด้งตอนยิง, วาบเขียวตอนเก็บกระสุน, ส้ม/แดงตอนใกล้หมด
# - แถบรีโหลดวิ่งแทนแถวหัวกระสุนตอนรีโหลด

@export var margin := Vector2(28, 28)           # ระยะจากมุมขวาล่างของจอ
@export var panel_size := Vector2(250, 96)
@export var low_ammo_ratio := 0.34              # แม็กเหลือต่ำกว่านี้เริ่มเป็นสีส้ม

const PAD := 18.0
const MAG_FONT := 46
const RESERVE_FONT := 24
const PIP_GAP := 3.0

var _mag := 0
var _mag_size := 1
var _reserve := 0

var _punch := 0.0          # เลขเด้งตอนยิง
var _pickup_flash := 0.0   # วาบเขียวตอนได้กระสุน

var _weapon: Node
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

	# ปืนอยู่ที่ Player/Head/Camera3D (owner = Player)
	_weapon = owner.get_node("Head/Camera3D")
	_weapon.ammo_changed.connect(_on_ammo_changed)
	_weapon.emit_state()   # ขอค่าเริ่มต้น เพราะ weapon ส่งไปก่อนเราเชื่อมต่อ

func _on_ammo_changed(mag: int, mag_size: int, reserve: int) -> void:
	if mag < _mag:
		_punch = 1.0
	if reserve > _reserve:
		_pickup_flash = 1.0
	_mag = mag
	_mag_size = maxi(mag_size, 1)
	_reserve = reserve

func _process(delta: float) -> void:
	_punch = move_toward(_punch, 0.0, delta * 7.0)
	_pickup_flash = move_toward(_pickup_flash, 0.0, delta * 2.0)
	queue_redraw()

func _draw() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var font := ThemeDB.fallback_font
	var reloading: bool = _weapon.is_reloading()
	var empty := _mag <= 0
	var low := _mag <= ceili(_mag_size * low_ammo_ratio)

	var rect := Rect2(
		Vector2(size.x - margin.x - panel_size.x, size.y - margin.y - panel_size.y),
		panel_size
	)
	draw_style_box(_frame, rect)

	# วาบเขียวตอนเก็บกระสุน
	if _pickup_flash > 0.0:
		_style.bg_color = Color(0.3, 1.0, 0.45, 0.22 * _pickup_flash)
		_style.set_corner_radius_all(14)
		draw_style_box(_style, rect)

	# สีเลขหลัก
	var main_color := Color.WHITE
	if empty:
		main_color = Color(1.0, 0.25, 0.25).lerp(Color.WHITE, 0.5 + 0.5 * sin(t * 8.0)) if not reloading else Color(0.6, 0.6, 0.65)
	elif low:
		main_color = Color(1.0, 0.65, 0.2)
	main_color = main_color.lerp(Color(0.5, 1.0, 0.6), _pickup_flash * 0.6)

	# เลขในแม็ก (เด้งตอนยิง)
	var mag_text := str(_mag)
	var mag_font := int(MAG_FONT + _punch * 8.0)
	var base_pos := Vector2(rect.position.x + PAD, rect.position.y + 56.0)
	draw_string_outline(font, base_pos, mag_text, HORIZONTAL_ALIGNMENT_LEFT, -1, mag_font, 6, Color(0, 0, 0, 0.85))
	draw_string(font, base_pos, mag_text, HORIZONTAL_ALIGNMENT_LEFT, -1, mag_font, main_color)

	# กระสุนสำรอง
	var mag_w := font.get_string_size(mag_text, HORIZONTAL_ALIGNMENT_LEFT, -1, MAG_FONT).x
	var res_text := "/ %d" % _reserve
	var res_color := Color(0.75, 0.75, 0.8) if _reserve > 0 else Color(1.0, 0.3, 0.3)
	res_color = res_color.lerp(Color(0.5, 1.0, 0.6), _pickup_flash)
	var res_pos := Vector2(base_pos.x + mag_w + 10.0, base_pos.y - 2.0)
	draw_string_outline(font, res_pos, res_text, HORIZONTAL_ALIGNMENT_LEFT, -1, RESERVE_FONT, 4, Color(0, 0, 0, 0.85))
	draw_string(font, res_pos, res_text, HORIZONTAL_ALIGNMENT_LEFT, -1, RESERVE_FONT, res_color)

	# แถบล่าง: รีโหลด / ข้อความเตือน / หัวกระสุน
	var inner_w := rect.size.x - PAD * 2.0
	var bottom_y := rect.end.y - 24.0

	if reloading:
		var progress: float = _weapon.reload_progress()
		draw_string(font, Vector2(rect.position.x + PAD, bottom_y - 6.0), GameSettings.t("ammo.reloading"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.85, 0.9))
		_draw_pill(Rect2(rect.position.x + PAD, bottom_y, inner_w, 8.0), Color(0.15, 0.15, 0.18))
		_draw_pill(Rect2(rect.position.x + PAD, bottom_y, inner_w * progress, 8.0), Color(0.95, 0.85, 0.3))
	elif empty and _reserve > 0:
		var a := 0.55 + 0.45 * sin(t * 8.0)
		draw_string(font, Vector2(rect.position.x + PAD, bottom_y + 8.0), GameSettings.t("ammo.press_r"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.85, 0.3, a))
	elif empty:
		var a := 0.55 + 0.45 * sin(t * 8.0)
		draw_string(font, Vector2(rect.position.x + PAD, bottom_y + 8.0), GameSettings.t("ammo.none"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.3, 0.3, a))
	elif _mag_size <= 20:
		var pw := minf(14.0, (inner_w - PIP_GAP * (_mag_size - 1)) / _mag_size)
		for i in _mag_size:
			var pip := Rect2(rect.position.x + PAD + i * (pw + PIP_GAP), bottom_y, pw, 10.0)
			var c := main_color if i < _mag else Color(1, 1, 1, 0.13)
			_draw_pill(pip, c)

func _draw_pill(r: Rect2, color: Color) -> void:
	if r.size.x < 1.0:
		return
	_style.bg_color = color
	_style.set_corner_radius_all(int(minf(r.size.x, r.size.y) * 0.5))
	draw_style_box(_style, r)

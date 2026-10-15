extends Control

# หลอดเลือดมุมซ้ายบน วาดด้วยโค้ดล้วน (ไม่ต้องใช้รูป)
# - กรอบ/หลอดทรงแคปซูล ขอบโค้งมน มีเงา และเงาสะท้อนด้านบนหลอด
# - ไอคอนหัวใจในวงกลม เต้นเบาๆ เต้นเร็วตอนเลือดต่ำ และเด้งตอนโดนตี
# - แถบขาวหน่วง: ค่อยๆ ไหลลงตามหลังตอนโดนตี ให้เห็นว่าเสียไปเท่าไหร่
# - ขอบจอแดง (vignette) วาบตอนโดนตี และกะพริบตอนเลือดต่ำ

@export var bar_size := Vector2(300, 24)
@export var margin := Vector2(28, 28)           # ระยะจากมุมซ้ายบนของจอ
@export var ghost_delay := 0.5                  # วินาทีที่รอก่อนแถบขาวเริ่มไหลลง
@export var ghost_speed := 0.6                  # สัดส่วนหลอดต่อวินาที
@export var heal_speed := 2.5                   # ความเร็วหลอดเขียวไล่ขึ้นตอนฮิล
@export var low_health_ratio := 0.3             # ต่ำกว่านี้จอเริ่มกะพริบแดง
@export var hit_flash_strength := 0.9           # ความเข้มขอบจอแดงตอนโดนตี
@export var heart_color := Color(0.95, 0.15, 0.25)

const PADDING := 3.0       # ช่องว่างระหว่างกรอบกับหลอด
const BADGE_GAP := 6.0     # ช่องว่างระหว่างวงกลมหัวใจกับหลอด

var _cur := 100.0
var _max := 100.0
var _ratio := 1.0
var _fill := 1.0           # หลอดเลือดที่แสดงจริง (ตอนฮิลจะค่อยๆ ไล่ขึ้น)
var _ghost := 1.0          # แถบขาวหน่วง
var _ghost_timer := 0.0
var _flash := 0.0

var _style := StyleBoxFlat.new()          # ใช้วาดทรงแคปซูลธรรมดา (พื้น, แถบ, เงาสะท้อน)
var _frame := StyleBoxFlat.new()          # กรอบมีขอบ+เงา
var _vignette: GradientTexture2D
var _heart: PackedVector2Array

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

	_heart = _build_heart()
	_vignette = _build_vignette()

	# owner = Player (root ของ player.tscn) เหมือนที่ weapon.gd ใช้
	# player.gd จะส่ง signal ค่าเริ่มต้นใน _ready ของมัน ซึ่งรันหลังเรา จึงรับทัน
	owner.health_changed.connect(_on_health_changed)

func _on_health_changed(current: float, max_value: float, amount: float) -> void:
	_cur = current
	_max = max_value
	_ratio = clampf(current / max_value, 0.0, 1.0)

	if amount < 0.0:
		_fill = _ratio                       # โดนตี: หลอดจริงลดทันที
		_ghost_timer = ghost_delay
		_flash = clampf(-amount / max_value * 3.0, 0.35, 1.0)   # ยิ่งโดนแรง ยิ่งวาบแรง
	elif amount > 0.0:
		_ghost = maxf(_ghost, _ratio)        # ฮิล: แถบขาวบอกปลายทาง หลอดเขียวไล่ตามขึ้น
	else:
		_fill = _ratio                       # ค่าเริ่มต้น
		_ghost = _ratio

func _process(delta: float) -> void:
	_flash = move_toward(_flash, 0.0, delta * 2.5)

	if _fill < _ratio:
		_fill = move_toward(_fill, _ratio, heal_speed * delta)

	if _ghost_timer > 0.0:
		_ghost_timer -= delta
	elif _ghost > _ratio:
		_ghost = move_toward(_ghost, _ratio, ghost_speed * delta)

	queue_redraw()

# ---------------------------------------------------------------
# วาด
# ---------------------------------------------------------------
func _draw() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var low := _ratio <= low_health_ratio and _cur > 0.0

	# --- ขอบจอแดง ---
	var vignette_alpha := _flash * hit_flash_strength
	if low:
		vignette_alpha = maxf(vignette_alpha, (0.5 + 0.5 * sin(t * 5.0)) * 0.45)
	if vignette_alpha > 0.0:
		draw_texture_rect(_vignette, Rect2(Vector2.ZERO, size), false, Color(1, 1, 1, vignette_alpha))

	# --- ตำแหน่ง ---
	var badge_d := bar_size.y + 18.0                       # เส้นผ่านศูนย์กลางวงกลมหัวใจ
	var badge_rect := Rect2(margin, Vector2(badge_d, badge_d))
	var bar_pos := Vector2(
		badge_rect.end.x + BADGE_GAP + PADDING,
		badge_rect.get_center().y - bar_size.y * 0.5
	)

	# --- กรอบหลอด ---
	var frame_rect := Rect2(bar_pos - Vector2(PADDING, PADDING), bar_size + Vector2(PADDING, PADDING) * 2.0)
	_draw_frame(frame_rect)

	# --- พื้นหลังหลอด ---
	_draw_pill(Rect2(bar_pos, bar_size), Color(0.13, 0.13, 0.15, 1.0))

	# --- แถบขาวหน่วง ---
	_draw_pill(Rect2(bar_pos, Vector2(bar_size.x * _ghost, bar_size.y)), Color(1, 1, 1, 0.55))

	# --- เลือดจริง + เงาสะท้อน ---
	var fill_rect := Rect2(bar_pos, Vector2(bar_size.x * _fill, bar_size.y))
	_draw_pill(fill_rect, _bar_color())
	if fill_rect.size.x > 10.0:
		var shine := Rect2(
			fill_rect.position + Vector2(4.0, 3.0),
			Vector2(fill_rect.size.x - 8.0, bar_size.y * 0.32)
		)
		_draw_pill(shine, Color(1, 1, 1, 0.22))

	# --- ตัวเลข ---
	var font := ThemeDB.fallback_font
	var font_size := 15
	var text := "%d / %d" % [ceili(_cur), ceili(_max)]
	var text_pos := Vector2(bar_pos.x, bar_pos.y + bar_size.y * 0.5 + font_size * 0.36)
	draw_string_outline(font, text_pos, text, HORIZONTAL_ALIGNMENT_CENTER, bar_size.x, font_size, 4, Color(0, 0, 0, 0.85))
	draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_CENTER, bar_size.x, font_size, Color.WHITE)

	# --- วงกลมหัวใจ ---
	_draw_frame(badge_rect)

	var beat := 0.0
	if _cur <= 0.0:
		beat = 0.0
	elif low:
		beat = pow(maxf(0.0, sin(t * 9.0)), 3.0) * 0.20     # เต้นถี่ตอนเลือดต่ำ
	else:
		beat = pow(maxf(0.0, sin(t * 3.0)), 6.0) * 0.08     # เต้นช้าๆ
	var heart_r := badge_d * 0.30 * (1.0 + beat + _flash * 0.30)
	var heart_c := badge_rect.get_center()
	var main_color := heart_color if _cur > 0.0 else Color(0.35, 0.35, 0.38)
	_draw_heart(heart_c, heart_r * 1.14, Color(0, 0, 0, 0.6))   # ขอบดำของหัวใจ
	_draw_heart(heart_c, heart_r, main_color)
	_draw_heart(heart_c + Vector2(-heart_r * 0.28, -heart_r * 0.32), heart_r * 0.22, Color(1, 1, 1, 0.35))   # จุดแวว

# ทรงแคปซูล (โค้งเต็มปลาย) ถ้าสั้นมากจะลดรัศมีลงอัตโนมัติ
func _draw_pill(rect: Rect2, color: Color) -> void:
	if rect.size.x < 1.0:
		return
	_style.bg_color = color
	_style.set_corner_radius_all(int(minf(rect.size.x, rect.size.y) * 0.5))
	draw_style_box(_style, rect)

# กรอบมีขอบและเงา (ใช้ทั้งกรอบหลอดและวงกลมหัวใจ)
func _draw_frame(rect: Rect2) -> void:
	_frame.set_corner_radius_all(int(minf(rect.size.x, rect.size.y) * 0.5))
	draw_style_box(_frame, rect)

func _draw_heart(center: Vector2, radius: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for p in _heart:
		pts.append(center + p * radius)
	draw_colored_polygon(pts, color)

func _bar_color() -> Color:
	# เลือดเต็ม = เขียว ไล่ผ่านเหลืองไปแดงตอนใกล้หมด
	return Color.from_hsv(_fill * 0.33, 0.72, 0.92)

# ---------------------------------------------------------------
# สร้างของครั้งเดียวตอน _ready
# ---------------------------------------------------------------
func _build_heart() -> PackedVector2Array:
	# สมการหัวใจ ปรับให้อยู่ในช่วง -1..1 และจัดกึ่งกลาง
	var pts := PackedVector2Array()
	var n := 48
	for i in n:
		var a := TAU * float(i) / float(n)
		var x := 16.0 * pow(sin(a), 3.0)
		var y := 13.0 * cos(a) - 5.0 * cos(2.0 * a) - 2.0 * cos(3.0 * a) - cos(4.0 * a)
		pts.append(Vector2(x, -y) / 17.0 + Vector2(0.0, -0.15))
	return pts

func _build_vignette() -> GradientTexture2D:
	# วงรีโปร่งใสตรงกลาง ไล่เป็นแดงที่ขอบจอ
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([
		Color(0.85, 0.0, 0.0, 0.0),
		Color(0.85, 0.0, 0.0, 0.0),
		Color(0.85, 0.0, 0.0, 0.95),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	return tex

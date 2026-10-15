extends Control

# หน้าเลือกการ์ด วาดด้วยโค้ดล้วน สไตล์เดียวกับ HUD อื่น
# - เปิดด้วย open(options) การ์ดไหลขึ้นมาทีละใบ ปล่อยเมาส์ให้คลิกได้
# - เลือกด้วยเมาส์คลิก หรือกดปุ่ม 1 / 2 / 3
# - เลือกแล้ว: ใบที่เลือกวาบ แล้วการ์ดทั้งหมดย่อหาย -> ส่ง signal closed
# - signal picked ส่งทันทีที่เลือก (ให้ผลมีผลเลย) closed ส่งหลังย่อเสร็จ

signal picked(id: String)
signal closed

const CARD := Vector2(250, 340)
const GAP := 28.0
const INPUT_DELAY := 0.35      # กันคลิกพลาดตอนการ์ดเพิ่งขึ้น
const CLOSE_TIME := 0.32
const PAD := 18.0

var _opts: Array = []
var _open := false
var _t := 0.0
var _hover := -1
var _chosen := -1
var _close := 0.0   # 0..1 ความคืบหน้าตอนย่อหาย

var _style := StyleBoxFlat.new()
var _frame := StyleBoxFlat.new()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)
	visible = false

	_style.anti_aliasing = true

	_frame.anti_aliasing = true
	_frame.bg_color = Color(0.07, 0.07, 0.09, 0.95)
	_frame.set_border_width_all(3)
	_frame.border_color = Color(1, 1, 1, 0.22)
	_frame.shadow_color = Color(0, 0, 0, 0.5)
	_frame.shadow_size = 10
	_frame.shadow_offset = Vector2(0, 4)
	_frame.set_corner_radius_all(16)

func open(options: Array) -> void:
	_opts = options
	_open = true
	_t = 0.0
	_hover = -1
	_chosen = -1
	_close = 0.0
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP   # กินคลิกทั้งหมด player.gd จะได้ไม่จับเมาส์กลับ
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	queue_redraw()

func _finish() -> void:
	_open = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED   # คืนเมาส์ให้เล่นต่อ
	closed.emit()

func _process(delta: float) -> void:
	if not _open:
		return
	_t += delta

	if _chosen >= 0:
		_close += delta / CLOSE_TIME
		if _close >= 1.0:
			_finish()
			return
	elif _t > INPUT_DELAY:
		_hover = _card_at(get_local_mouse_position())

	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed \
		and _chosen < 0 and _t > INPUT_DELAY:
			var i := _card_at(event.position)
			if i >= 0:
				_select(i)
		accept_event()

func _input(event: InputEvent) -> void:
	if not _open or _chosen >= 0 or _t <= INPUT_DELAY:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var i := -1
		match event.keycode:
			KEY_1, KEY_KP_1: i = 0
			KEY_2, KEY_KP_2: i = 1
			KEY_3, KEY_KP_3: i = 2
		if i >= 0 and i < _opts.size():
			_select(i)
			get_viewport().set_input_as_handled()

func _select(i: int) -> void:
	_chosen = i
	_close = 0.0
	picked.emit(_opts[i].id)

# ---------------------------------------------------------------
# ตำแหน่ง
# ---------------------------------------------------------------
func _card_center(i: int) -> Vector2:
	var n := _opts.size()
	var total_w := n * CARD.x + (n - 1) * GAP
	var x := size.x * 0.5 - total_w * 0.5 + CARD.x * 0.5 + i * (CARD.x + GAP)
	return Vector2(x, size.y * 0.5 + 10.0)

func _card_at(p: Vector2) -> int:
	for i in _opts.size():
		var r := Rect2(_card_center(i) - CARD * 0.5, CARD)
		if r.has_point(p):
			return i
	return -1

# ---------------------------------------------------------------
# วาด
# ---------------------------------------------------------------
func _draw() -> void:
	if not _open:
		return

	# ฉากมืดข้างหลัง
	var dim := clampf(_t / 0.25, 0.0, 1.0) * (1.0 - _close)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6 * dim))

	var head_alpha := dim
	_text_c(GameSettings.t("card.choose"), size.x * 0.5, size.y * 0.5 - CARD.y * 0.5 - 44.0, 38, Color(1, 1, 1, head_alpha), 6, head_alpha)
	_text_c(GameSettings.t("card.hint"), size.x * 0.5, size.y * 0.5 - CARD.y * 0.5 - 14.0, 16, Color(0.75, 0.75, 0.82, head_alpha), 3, head_alpha)

	for i in _opts.size():
		_draw_card(i)

func _draw_card(i: int) -> void:
	var o: Dictionary = _opts[i]
	var accent: Color = o.color
	var center := _card_center(i)

	# ไหลขึ้นมาทีละใบ
	var appear := clampf((_t - i * 0.09) / 0.3, 0.0, 1.0)
	appear = 1.0 - pow(1.0 - appear, 3.0)
	var s := lerpf(0.85, 1.0, appear)
	var rise := (1.0 - appear) * 40.0
	var alpha := appear

	var hovered := i == _hover and _chosen < 0
	if hovered:
		s *= 1.05

	# ตอนย่อหาย: ใบที่เลือกขยายวาบก่อนแล้วหด ใบอื่นหดเร็วกว่า
	if _chosen >= 0:
		if i == _chosen:
			s *= 1.0 + sin(clampf(_close, 0.0, 1.0) * PI) * 0.15 - _close * 0.95
		else:
			s *= maxf(1.0 - _close * 1.6, 0.0)
		alpha *= 1.0 - _close * 0.6
	s = maxf(s, 0.0)
	if s <= 0.01:
		return

	draw_set_transform(center + Vector2(0, rise), 0.0, Vector2(s, s))
	var r := Rect2(-CARD * 0.5, CARD)

	_frame.border_color = accent if (hovered or i == _chosen) else Color(1, 1, 1, 0.22)
	_frame.border_color.a *= alpha
	_frame.bg_color.a = 0.95 * alpha
	draw_style_box(_frame, r)

	# แถบสีด้านบน
	_pill(Rect2(r.position.x + PAD, r.position.y + PAD, CARD.x - PAD * 2.0, 8.0), Color(accent, alpha))

	# เลขปุ่มลัด
	_text_l(str(i + 1), r.position.x + PAD + 2.0, r.position.y + 58.0, 20, Color(0.7, 0.7, 0.78, alpha), 3, alpha)

	# ชื่อการ์ด (ย่อฟอนต์ถ้ายาวเกิน)
	var title: String = GameSettings.t("card.%s.title" % o.id)
	var fs := 26
	var font := ThemeDB.fallback_font
	while fs > 14 and font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > CARD.x - PAD * 2.0:
		fs -= 1
	_text_c(title, 0.0, r.position.y + 100.0, fs, Color(1, 1, 1, alpha), 5, alpha)

	# ตัวเลขใหญ่กลางการ์ด
	var big_color := accent.lerp(Color.WHITE, 0.15 if hovered else 0.0)
	big_color.a = alpha
	_text_c(o.big, 0.0, 30.0, 64, big_color, 8, alpha)
	_text_c(GameSettings.t("card.%s.unit" % o.id), 0.0, 66.0, 18, Color(0.85, 0.85, 0.92, alpha), 4, alpha)

	# สถานะสแตก
	var owned: int = o.owned
	var line: String = GameSettings.t("card.new") if owned == 0 \
		else GameSettings.t("card.owned") % [owned, owned + 1]
	var line_color := Color(0.5, 1.0, 0.6, alpha) if owned == 0 else Color(1.0, 0.85, 0.35, alpha)
	_pill(Rect2(-CARD.x * 0.5 + PAD, r.end.y - PAD - 36.0, CARD.x - PAD * 2.0, 36.0), Color(1, 1, 1, 0.07 * alpha))
	_text_c(line, 0.0, r.end.y - PAD - 11.0, 16, line_color, 3, alpha)

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

func _text_l(text: String, x: float, y: float, font_size: int, color: Color, outline: int = 4, alpha: float = 1.0) -> void:
	var font := ThemeDB.fallback_font
	var pos := Vector2(x, y)
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline, Color(0, 0, 0, 0.85 * alpha))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _pill(r: Rect2, color: Color) -> void:
	if r.size.x < 1.0:
		return
	_style.bg_color = color
	_style.set_corner_radius_all(int(minf(r.size.x, r.size.y) * 0.5))
	draw_style_box(_style, r)

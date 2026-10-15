extends Control

# GUI สแตกความสามารถมุมซ้ายล่าง วาดด้วยโค้ดล้วน สไตล์เดียวกับ HUD อื่น
# - แสดงเฉพาะอันที่เลือกแล้ว เรียงตามลำดับที่เลือกครั้งแรก
# - แต่ละแถว: จุดสี + ชื่อ + จำนวนสแตก (x2) + ค่ารวม (+40%)
# - แถวที่เพิ่งเลือก/สแตกเพิ่มจะวาบสว่างแล้วจางลง
# - UpgradeManager เรียก bind() ให้เอง

@export var margin := Vector2(28, 28)   # ระยะจากมุมซ้ายล่างของจอ

const PANEL_W := 270.0
const ROW_H := 28.0
const HEAD_H := 38.0
const PAD := 16.0

var _um: Node
var _pop := {}   # id -> 1..0 ความสว่างวาบ

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

func bind(um: Node) -> void:
	_um = um
	um.upgrade_chosen.connect(_on_chosen)

func _on_chosen(id: String, _n: int) -> void:
	_pop[id] = 1.0

func _process(delta: float) -> void:
	for id in _pop.keys():
		_pop[id] = move_toward(_pop[id], 0.0, delta * 1.2)
	queue_redraw()

func _draw() -> void:
	if _um == null or _um.stacks.is_empty():
		return

	var font := ThemeDB.fallback_font
	var rows: int = _um.stacks.size()
	var h := HEAD_H + rows * ROW_H + 10.0
	var rect := Rect2(Vector2(margin.x, size.y - margin.y - h), Vector2(PANEL_W, h))
	draw_style_box(_frame, rect)

	draw_string(font, Vector2(rect.position.x + PAD, rect.position.y + 25.0), GameSettings.t("stats.title"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.72, 0.72, 0.8))

	var i := 0
	for id in _um.stacks.keys():
		var n: int = _um.stacks[id]
		var d: Dictionary = _um.def_of(id)
		var accent: Color = d.color
		var pop: float = _pop.get(id, 0.0)

		var y := rect.position.y + HEAD_H + i * ROW_H
		var base := y + 19.0

		# พื้นวาบตอนสแตกเพิ่ม
		if pop > 0.0:
			_pill(Rect2(rect.position.x + 6.0, y, PANEL_W - 12.0, ROW_H - 2.0), Color(accent, 0.28 * pop))

		# จุดสี
		draw_circle(Vector2(rect.position.x + PAD + 5.0, y + ROW_H * 0.5 - 1.0), 5.0 + pop * 2.0, accent)

		# ชื่อ
		var name_txt: String = GameSettings.t("card.%s.short" % id)
		var tx := rect.position.x + PAD + 20.0
		var name_color := Color(0.88, 0.88, 0.94).lerp(Color.WHITE, pop)
		draw_string_outline(font, Vector2(tx, base), name_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 3, Color(0, 0, 0, 0.85))
		draw_string(font, Vector2(tx, base), name_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, name_color)

		# จำนวนสแตก
		var nw := font.get_string_size(name_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		if n > 1:
			draw_string(font, Vector2(tx + nw + 6.0, base), "x%d" % n,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.85, 0.35))

		# ค่ารวม (ชิดขวา)
		var total: String = _um.total_text(id, n)
		var tc := accent.lerp(Color.WHITE, 0.25 + pop * 0.5)
		var rw := PANEL_W - PAD * 2.0
		draw_string_outline(font, Vector2(rect.position.x + PAD, base), total, HORIZONTAL_ALIGNMENT_RIGHT, rw, 15, 4, Color(0, 0, 0, 0.85))
		draw_string(font, Vector2(rect.position.x + PAD, base), total, HORIZONTAL_ALIGNMENT_RIGHT, rw, 15, tc)

		i += 1

func _pill(r: Rect2, color: Color) -> void:
	if r.size.x < 1.0:
		return
	_style.bg_color = color
	_style.set_corner_radius_all(int(minf(r.size.x, r.size.y) * 0.5))
	draw_style_box(_style, r)

extends Node

# ป้าย Title เหนือไอเทมเวลาเล็งไปที่มัน (สร้างให้อัตโนมัติโดย pickup.gd ไม่ต้องเพิ่ม node เอง)
# - เมาส์ล็อกกลางจอ = ใช้จุดกึ่งกลางจอ (ครอสแฮร์), ถ้าปล่อยเมาส์ (ESC) = ใช้ตำแหน่งเมาส์จริง
# - ป้ายอยู่เหนือไอเทมเสมอ ขนาดคงที่ อ่านง่ายทั้งใกล้และไกล

@export var hover_range := 40.0       # ไกลสุดที่ชี้แล้วขึ้นป้าย (เมตร)
@export var aim_tolerance := 0.012    # ยิ่งไกลยิ่งชี้ง่ายขึ้นเล็กน้อย (เรเดียน)
@export var title_size := 26
@export var desc_size := 18

var _layer: CanvasLayer
var _ui: Control
var _alpha := 0.0
var _snap := {}
var _style := StyleBoxFlat.new()

func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 2
	add_child(_layer)

	_ui = Control.new()
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_ui)
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.draw.connect(_on_draw)

	_style.anti_aliasing = true
	_style.bg_color = Color(0.06, 0.06, 0.08, 0.92)
	_style.set_border_width_all(2)
	_style.set_corner_radius_all(10)
	_style.shadow_color = Color(0, 0, 0, 0.5)
	_style.shadow_size = 6

func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var best = null
	if cam != null:
		best = _find_hovered(cam)

	if best != null:
		var center: Vector3 = best.hover_center()
		_snap = {
			"pos": center,
			"title": best.title_text(),
			"desc": best.desc_text(),
			"status": best.status_text(),
			"color": best.accent_color(),
			"dist": cam.global_position.distance_to(center),
		}
		_alpha = move_toward(_alpha, 1.0, delta * 10.0)
	else:
		_alpha = move_toward(_alpha, 0.0, delta * 7.0)

	_ui.modulate.a = _alpha
	_ui.queue_redraw()

# หาไอเทมที่อยู่ใต้ครอสแฮร์ (ตรวจแบบเรขาคณิต ไม่ต้องใช้ collision) เลือกตัวที่ใกล้สุด
func _find_hovered(cam: Camera3D):
	var vp := get_viewport()
	var mp := vp.get_mouse_position()
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mp = vp.get_visible_rect().size * 0.5

	var origin := cam.project_ray_origin(mp)
	var dir := cam.project_ray_normal(mp)

	var best = null
	var best_t := hover_range
	for p in get_tree().get_nodes_in_group("pickup"):
		var to: Vector3 = p.hover_center() - origin
		var t := to.dot(dir)
		if t < 0.3 or t > best_t:
			continue
		var perp := (to - dir * t).length()
		if perp <= p.hover_radius + t * aim_tolerance:
			best = p
			best_t = t
	return best

func _on_draw() -> void:
	if _alpha <= 0.01 or _snap.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var wp: Vector3 = _snap.pos
	if cam.is_position_behind(wp):
		return

	var sp := cam.unproject_position(wp)
	var up := cam.unproject_position(wp + Vector3.UP * 0.6)
	var lift := clampf(sp.y - up.y, 18.0, 160.0) + 16.0

	var font := ThemeDB.fallback_font
	var title: String = _snap.title
	var status: String = _snap.status
	var blocked := status != ""
	var desc: String = status if blocked else _snap.desc
	var accent: Color = _snap.color
	var dist_txt := "%d m" % int(round(_snap.dist))

	var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x
	var dw := font.get_string_size(desc, HORIZONTAL_ALIGNMENT_LEFT, -1, desc_size).x
	var mw := font.get_string_size(dist_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var row_w := dw + 18.0 + mw

	var pad := 20.0
	var w := maxf(tw, row_w) + pad * 2.0
	var h := 82.0
	var x := clampf(sp.x - w * 0.5, 8.0, maxf(_ui.size.x - w - 8.0, 8.0))
	var y := maxf(sp.y - lift - h - 10.0 + (1.0 - _alpha) * 8.0, 8.0)

	var border := accent if not blocked else Color(0.6, 0.6, 0.66)
	_style.border_color = border
	_ui.draw_style_box(_style, Rect2(x, y, w, h))

	# ลูกศรชี้ลงหาไอเทม
	var px := clampf(sp.x, x + 18.0, x + w - 18.0)
	_ui.draw_colored_polygon(PackedVector2Array([
		Vector2(px - 9.0, y + h - 1.0),
		Vector2(px + 9.0, y + h - 1.0),
		Vector2(px, y + h + 11.0),
	]), border)

	# Title
	var tpos := Vector2(x + (w - tw) * 0.5, y + 38.0)
	_ui.draw_string_outline(font, tpos, title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, 6, Color(0, 0, 0, 0.9))
	_ui.draw_string(font, tpos, title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, Color.WHITE)

	# รายละเอียด + ระยะ
	var rx := x + (w - row_w) * 0.5
	var desc_color := accent.lerp(Color.WHITE, 0.25) if not blocked else Color(1.0, 0.5, 0.5)
	var dpos := Vector2(rx, y + 66.0)
	_ui.draw_string_outline(font, dpos, desc, HORIZONTAL_ALIGNMENT_LEFT, -1, desc_size, 4, Color(0, 0, 0, 0.9))
	_ui.draw_string(font, dpos, desc, HORIZONTAL_ALIGNMENT_LEFT, -1, desc_size, desc_color)
	_ui.draw_string(font, Vector2(rx + dw + 18.0, y + 66.0), dist_txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.7, 0.76))

class_name UiTheme
extends RefCounted

# ตัวช่วยสร้าง UI แบบ Control จริง (ปุ่ม / ป้าย / กรอบ) สไตล์เดียวกับ HUD ทั้งเกม
# ใช้ร่วมกันระหว่างเมนูหยุดเกม เมนูหลัก และหน้าตั้งค่า
# วิธีใช้: ตั้ง theme = UiTheme.make_theme() ที่ Control ราก ลูกๆ จะได้สไตล์ตามอัตโนมัติ

const ACCENT := Color(1.0, 0.82, 0.3)
const TEXT := Color(0.9, 0.9, 0.95)

static func box(bg: Color, border: Color, radius: int = 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	return sb

static func label(text: String, font_size: int = 20, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l

static func title(text: String, font_size: int = 40) -> Label:
	var l := label(text, font_size, Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	return l

static func button(text: String, cb: Callable, toggle := false, on := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 50)
	if toggle:
		b.toggle_mode = true
		b.button_pressed = on
	b.pressed.connect(cb)
	return b

# ตัวจัดกึ่งกลาง > กรอบ > ขอบใน > VBox แล้วคืน VBox ให้ใส่เนื้อหา
static func build_centered_panel(parent: Control, min_width: float) -> VBoxContainer:
	var center := CenterContainer.new()
	parent.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(min_width, 0)
	var sb := box(Color(0.07, 0.07, 0.09, 0.96), Color(1, 1, 1, 0.22), 18)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 12
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 30)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	margin.add_child(content)
	return content

static func make_theme() -> Theme:
	var th := Theme.new()

	th.set_font_size("font_size", "Button", 22)
	th.set_font_size("font_size", "Label", 20)
	th.set_color("font_color", "Button", TEXT)
	th.set_color("font_hover_color", "Button", Color.WHITE)
	th.set_color("font_focus_color", "Button", Color.WHITE)
	th.set_color("font_pressed_color", "Button", Color(0.1, 0.1, 0.12))
	th.set_color("font_hover_pressed_color", "Button", Color(0.1, 0.1, 0.12))

	th.set_stylebox("normal", "Button", box(Color(0.14, 0.14, 0.17), Color(1, 1, 1, 0.15)))
	th.set_stylebox("hover", "Button", box(Color(0.2, 0.2, 0.25), ACCENT))
	th.set_stylebox("pressed", "Button", box(ACCENT, ACCENT))
	th.set_stylebox("hover_pressed", "Button", box(ACCENT.lightened(0.15), ACCENT))
	th.set_stylebox("disabled", "Button", box(Color(0.1, 0.1, 0.12), Color(1, 1, 1, 0.08)))
	var focus := box(Color(0, 0, 0, 0), ACCENT)
	focus.draw_center = false
	th.set_stylebox("focus", "Button", focus)

	var track := box(Color(0.16, 0.16, 0.19), Color(1, 1, 1, 0.1), 6)
	track.content_margin_top = 4.0
	track.content_margin_bottom = 4.0
	var fill := box(ACCENT, ACCENT, 6)
	fill.content_margin_top = 4.0
	fill.content_margin_bottom = 4.0
	th.set_stylebox("slider", "HSlider", track)
	th.set_stylebox("grabber_area", "HSlider", fill)
	th.set_stylebox("grabber_area_highlight", "HSlider", fill)

	return th

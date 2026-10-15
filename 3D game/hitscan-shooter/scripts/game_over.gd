extends Control

# หน้าจอตาย (Game Over) สร้างด้วยโค้ดล้วน WaveManager สร้างให้เอง ไม่ต้องลาก node
# - แสดง 2 ค่า: Wave ที่ไปถึง และเวลาที่รอดชีวิต
# - ปุ่มเดียว: กลับเมนูหลัก
# - WaveManager เรียก show_result(wave, seconds) หลังผู้เล่นตายไปครู่หนึ่ง
# - หยุดเกมด้วย get_tree().paused (ตัวหน้านี้ process_mode = ALWAYS จึงยังคลิกได้)

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const FADE_TIME := 0.6

var _content: VBoxContainer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UiTheme.make_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP   # กินคลิกทั้งหมด player.gd จะได้ไม่จับเมาส์กลับ
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false

	var dim := ColorRect.new()
	dim.color = Color(0.08, 0.0, 0.0, 0.74)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_content = UiTheme.build_centered_panel(self, 560)

func show_result(wave: int, seconds: float) -> void:
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()

	var title := UiTheme.title(GameSettings.t("over.title"), 52)
	title.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	_content.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	_content.add_child(spacer)

	_content.add_child(_stat_row(GameSettings.t("over.wave"), str(wave)))
	_content.add_child(_stat_row(GameSettings.t("over.time"), _format_time(seconds)))

	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 8)
	_content.add_child(spacer2)

	var btn := UiTheme.button(GameSettings.t("over.menu"), _on_main_menu)
	_content.add_child(btn)

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	modulate.a = 0.0
	visible = true
	create_tween().tween_property(self, "modulate:a", 1.0, FADE_TIME)
	btn.grab_focus.call_deferred()

func _on_main_menu() -> void:
	GameSettings.save()
	GameStats.save()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)

# ---------------------------------------------------------------
# ตัวช่วย
# ---------------------------------------------------------------
func _stat_row(label_text: String, value_text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var l := UiTheme.label(label_text, 22)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)

	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(200, 0)
	badge.add_theme_stylebox_override("panel", UiTheme.box(Color(0.14, 0.14, 0.17), Color(1, 1, 1, 0.15), 10))
	var v := UiTheme.label(value_text, 26, UiTheme.ACCENT)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_child(v)
	row.add_child(badge)
	return row

func _format_time(seconds: float) -> String:
	var s := int(seconds)
	var h := s / 3600
	var m := (s % 3600) / 60
	var sec := s % 60
	if h > 0:
		return GameSettings.t("stats.time_hms") % [h, m, sec]
	return GameSettings.t("stats.time_ms") % [m, sec]

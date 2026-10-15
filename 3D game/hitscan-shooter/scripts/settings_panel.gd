class_name SettingsPanel
extends VBoxContainer

# หน้าตั้งค่า (ใช้ร่วมกันทั้งเมนูหยุดเกมและเมนูหลัก)
# - 4 แท็บ: Language (EN/TH) / Display (ความสว่าง) / Audio (หลัก/เพลง/เอฟเฟกต์) / Controls (รายการปุ่ม)
# - สร้างตัวเองในโค้ด แค่ add_child(SettingsPanel.new()) แล้วฟัง signal back_pressed
# - ต้องอยู่ใต้ Control ที่ตั้ง theme = UiTheme.make_theme() ไว้แล้ว

signal back_pressed
signal language_changed

const TABS := ["language", "display", "audio", "controls"]
const LANG_NAMES := {"en": "English", "th": "ไทย"}

# [action ใน Input Map, key ใน GameSettings.STRINGS]
const CONTROL_ROWS := [
	["move_forward", "ctl.forward"],
	["move_back", "ctl.back"],
	["move_left", "ctl.left"],
	["move_right", "ctl.right"],
	["jump", "ctl.jump"],
	["sprint", "ctl.sprint"],
	["crouch", "ctl.crouch"],
	["shoot", "ctl.shoot"],
	["reload", "ctl.reload"],
]

var _tab := "language"

func _ready() -> void:
	add_theme_constant_override("separation", 14)
	_rebuild()

func _rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()

	add_child(UiTheme.title(GameSettings.t("set.title")))

	# แถบแท็บ
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	for id in TABS:
		var b := UiTheme.button(GameSettings.t("tab." + id), _on_tab.bind(id), true, _tab == id)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 17)
		tabs.add_child(b)
	add_child(tabs)

	# เนื้อหาแท็บ
	var body := VBoxContainer.new()
	body.custom_minimum_size = Vector2(0, 330)
	body.add_theme_constant_override("separation", 18)
	add_child(body)

	match _tab:
		"language": _fill_language(body)
		"display": _fill_display(body)
		"audio": _fill_audio(body)
		"controls": _fill_controls(body)

	add_child(UiTheme.button(GameSettings.t("set.back"), _on_back))

func _fill_language(body: VBoxContainer) -> void:
	body.add_child(UiTheme.label(GameSettings.t("lang.choose")))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	for code in ["en", "th"]:
		var b := UiTheme.button(LANG_NAMES[code], _on_language.bind(code), true, GameSettings.language == code)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	body.add_child(row)

func _fill_display(body: VBoxContainer) -> void:
	_slider_row(body, GameSettings.t("disp.brightness"), GameSettings.brightness, 0.5, 1.5, _on_brightness)

func _fill_audio(body: VBoxContainer) -> void:
	_slider_row(body, GameSettings.t("aud.master"), GameSettings.vol_master, 0.0, 1.0, _on_volume.bind("master"))
	_slider_row(body, GameSettings.t("aud.music"), GameSettings.vol_music, 0.0, 1.0, _on_volume.bind("music"))
	_slider_row(body, GameSettings.t("aud.sfx"), GameSettings.vol_sfx, 0.0, 1.0, _on_volume.bind("sfx"))

func _fill_controls(body: VBoxContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 330)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)

	for pair in CONTROL_ROWS:
		if InputMap.has_action(pair[0]):
			list.add_child(_key_row(GameSettings.t(pair[1]), _keys_text(pair[0])))
	list.add_child(_key_row(GameSettings.t("ctl.card"), "1 / 2 / 3"))
	list.add_child(_key_row(GameSettings.t("ctl.pause"), "Esc"))

# ---------------------------------------------------------------
# ปุ่มกด / ตัวเลื่อน
# ---------------------------------------------------------------
func _on_back() -> void:
	GameSettings.save()
	back_pressed.emit()

func _on_tab(id: String) -> void:
	_tab = id
	_rebuild()

func _on_language(code: String) -> void:
	GameSettings.language = code
	GameSettings.save()
	_rebuild()
	language_changed.emit()

func _on_brightness(value: float) -> void:
	GameSettings.brightness = value
	GameSettings.apply_brightness(get_tree())

func _on_volume(value: float, which: String) -> void:
	match which:
		"master": GameSettings.vol_master = value
		"music": GameSettings.vol_music = value
		"sfx": GameSettings.vol_sfx = value
	GameSettings.apply_audio()

# ---------------------------------------------------------------
# ข้อความชื่อปุ่มจาก Input Map
# ---------------------------------------------------------------
func _keys_text(action: String) -> String:
	var parts: Array[String] = []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var code: int = ev.get_physical_keycode_with_modifiers() if ev.physical_keycode != KEY_NONE \
				else ev.get_keycode_with_modifiers()
			parts.append(OS.get_keycode_string(code))
		elif ev is InputEventMouseButton:
			match ev.button_index:
				MOUSE_BUTTON_LEFT: parts.append(GameSettings.t("key.lmb"))
				MOUSE_BUTTON_RIGHT: parts.append(GameSettings.t("key.rmb"))
				MOUSE_BUTTON_MIDDLE: parts.append(GameSettings.t("key.mmb"))
				_: parts.append(ev.as_text())
		else:
			parts.append(ev.as_text())
	return " / ".join(parts) if not parts.is_empty() else "-"

# ---------------------------------------------------------------
# ตัวช่วยสร้างแถว
# ---------------------------------------------------------------
func _slider_row(parent: Control, text: String, value: float, lo: float, hi: float, on_change: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)

	var l := UiTheme.label(text)
	l.custom_minimum_size.x = 190.0
	row.add_child(l)

	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.01
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(200, 28)
	row.add_child(s)

	var v := UiTheme.label("%d%%" % roundi(value * 100.0), 20, UiTheme.ACCENT)
	v.custom_minimum_size.x = 64.0
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(v)

	s.value_changed.connect(func(x: float) -> void:
		v.text = "%d%%" % roundi(x * 100.0)
		on_change.call(x)
	)
	s.drag_ended.connect(func(_changed: bool) -> void:
		GameSettings.save()
	)
	parent.add_child(row)

func _key_row(action_text: String, key_text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var l := UiTheme.label(action_text)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)

	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(190, 0)
	badge.add_theme_stylebox_override("panel", UiTheme.box(Color(0.14, 0.14, 0.17), Color(1, 1, 1, 0.15), 10))
	var k := UiTheme.label(key_text, 19, UiTheme.ACCENT)
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_child(k)
	row.add_child(badge)
	return row

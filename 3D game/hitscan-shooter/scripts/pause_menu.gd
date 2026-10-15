extends Control

# เมนูหยุดเกม (กด ESC) สร้างด้วยโค้ดล้วน WaveManager สร้างให้เอง ไม่ต้องลาก node
# - หน้าหลัก: Resume / Settings / Main Menu / Quit Game
# - Settings ใช้ SettingsPanel (ตัวเดียวกับเมนูหลัก) มี 4 แท็บ ภาษา/หน้าจอ/เสียง/ปุ่มควบคุม
# - หยุดเกมด้วย get_tree().paused (ตัวเมนูตั้ง process_mode = ALWAYS จึงยังทำงานตอนหยุด)
# - Main Menu: กลับไป MAIN_MENU_SCENE (ถ้าไม่มีไฟล์ จะขึ้นข้อความแจ้งเฉยๆ)
# - locked = true (WaveManager ตั้งตอนผู้เล่นตาย) จะกด ESC เปิดเมนูนี้ไม่ได้ เพราะมีหน้า Game Over แทน

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

var locked := false      # true = ห้ามเปิดเมนู (ผู้เล่นตายแล้ว)

var _page := "main"      # "main" / "settings"
var _prev_mouse := Input.MOUSE_MODE_CAPTURED

var _content: VBoxContainer
var _notice: Label
var _notice_text := ""
var _notice_time := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # ต้องยังรับ input ตอนเกมหยุด
	GameSettings.ensure_loaded()
	_apply_saved_brightness.call_deferred()   # รอให้ WorldEnvironment ในฉากพร้อมก่อน

	theme = UiTheme.make_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_content = UiTheme.build_centered_panel(self, 600)

func _apply_saved_brightness() -> void:
	GameSettings.apply_brightness(get_tree())

func _process(delta: float) -> void:
	if _notice_time > 0.0:
		_notice_time -= delta
		if _notice_time <= 0.0:
			_notice_text = ""
	if is_instance_valid(_notice):
		_notice.text = _notice_text

func _input(event: InputEvent) -> void:
	if locked:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if not visible:
			_open()
		elif _page == "settings":
			_on_back()
		else:
			_resume()

# ---------------------------------------------------------------
# เปิด / ปิด
# ---------------------------------------------------------------
func _open() -> void:
	_prev_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	_page = "main"
	_notice_text = ""
	_notice_time = 0.0
	visible = true
	_rebuild()

func _resume() -> void:
	GameSettings.save()
	get_tree().paused = false
	visible = false
	Input.mouse_mode = _prev_mouse   # ถ้าก่อนหยุดเมาส์ถูกล็อกอยู่ ก็ล็อกกลับ

# ---------------------------------------------------------------
# สร้างหน้า
# ---------------------------------------------------------------
func _rebuild() -> void:
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	_notice = null
	if _page == "main":
		_build_main()
	else:
		var sp := SettingsPanel.new()
		sp.back_pressed.connect(_on_back)
		_content.add_child(sp)

func _build_main() -> void:
	_content.add_child(UiTheme.title(GameSettings.t("pause.title")))

	var first := UiTheme.button(GameSettings.t("pause.resume"), _resume)
	_content.add_child(first)
	_content.add_child(UiTheme.button(GameSettings.t("pause.settings"), _on_settings))
	_content.add_child(UiTheme.button(GameSettings.t("pause.main_menu"), _on_main_menu))
	_content.add_child(UiTheme.button(GameSettings.t("pause.quit"), _on_quit))

	_notice = UiTheme.label(_notice_text, 17, Color(1.0, 0.7, 0.4))
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(_notice)

	first.grab_focus.call_deferred()

# ---------------------------------------------------------------
# ปุ่มกด
# ---------------------------------------------------------------
func _on_settings() -> void:
	_page = "settings"
	_rebuild()

func _on_back() -> void:
	GameSettings.save()
	_page = "main"
	_rebuild()

func _on_main_menu() -> void:
	if ResourceLoader.exists(MAIN_MENU_SCENE):
		GameSettings.save()
		GameStats.save()
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)
	else:
		_notice_text = GameSettings.t("pause.no_menu")
		_notice_time = 2.5

func _on_quit() -> void:
	GameSettings.save()
	GameStats.save()
	get_tree().quit()

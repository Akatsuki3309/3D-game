extends Control

# หน้าเมนูหลัก สร้างด้วยโค้ดล้วน
# - ฉากหลัง: menu_backdrop.gd (ท้องฟ้า ดาวเคราะห์ ซากเมือง ฝุ่น) วาดด้วยโค้ด
# - ฝั่งขวา: โมเดลมอนเอเลี่ยนตัวจริงใน SubViewport (สุ่มมา 1 ตัวทุกครั้งที่เปิดเมนู)
#   หมุนตามเมาส์เบาๆ และทำท่าง้างโจมตีเป็นระยะ
# - ฝั่งซ้าย: ชื่อเกมใหญ่เรืองแสง + ปุ่ม Start / Settings / Statistics / Quit
# - Statistics อ่านจาก GameStats, Settings ใช้ SettingsPanel ตัวเดียวกับเมนูหยุดเกม
#   (สองหน้านี้แสดงในกรอบกลางจอเหมือนเดิม)
# - ตั้งเป็นฉากเริ่มเกม: Project Settings > Application > Run > Main Scene = main_menu.tscn

const GAME_SCENE := "res://scenes/world.tscn"
const BackdropScript := preload("res://scripts/menu_backdrop.gd")

const LEFT_MARGIN := 90
const BUTTON_SIZE := Vector2(380, 56)
const POSE_INTERVAL := 4.0     # ทุกกี่วินาทีที่มอนทำท่าง้าง

var _page := "main"   # "main" / "settings" / "stats"
var _content: VBoxContainer       # เนื้อหาหน้า settings / stats (อยู่ในกรอบกลางจอ)
var _panel_root: Control          # กรอบกลางจอทั้งก้อน (ซ่อนตอนอยู่หน้าหลัก)
var _main_root: Control           # เลย์เอาต์หน้าหลัก (ชิดซ้าย)
var _main_box: VBoxContainer
var _showcase: Control            # ตัวโชว์มอน 3D (ซ่อนตอนอยู่หน้า settings / stats)

# --- โชว์มอน 3D ---
var _viewport: SubViewport
var _cam: Camera3D
var _enemy: EnemyBase
var _enemy_h := 1.9
var _t := 0.0
var _m := Vector2.ZERO

func _ready() -> void:
	GameSettings.ensure_loaded()
	GameStats.ensure_loaded()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE   # กลับมาจากเกมที่ล็อกเมาส์อยู่

	theme = UiTheme.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := BackdropScript.new()
	add_child(bg)

	_build_showcase()

	# เลย์เอาต์หน้าหลัก: ชิดซ้าย กึ่งกลางแนวตั้ง
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", LEFT_MARGIN)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_main_root = margin

	_main_box = VBoxContainer.new()
	_main_box.add_theme_constant_override("separation", 14)
	_main_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_main_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	margin.add_child(_main_box)

	# กรอบกลางจอ (settings / stats)
	_content = UiTheme.build_centered_panel(self, 560)
	_panel_root = _content.get_parent().get_parent().get_parent() as Control

	# จังหวะทำท่าของมอน
	var timer := Timer.new()
	timer.wait_time = POSE_INTERVAL
	timer.autostart = true
	timer.timeout.connect(_pose_enemy)
	add_child(timer)

	_rebuild()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _page != "main":
		get_viewport().set_input_as_handled()
		_go("main")

func _go(page: String) -> void:
	_page = page
	_rebuild()

func _rebuild() -> void:
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	for c in _main_box.get_children():
		_main_box.remove_child(c)
		c.queue_free()

	var is_main := _page == "main"
	_main_root.visible = is_main
	_showcase.visible = is_main
	_panel_root.visible = not is_main

	match _page:
		"main": _build_main()
		"settings": _build_settings()
		"stats": _build_stats()

# ---------------------------------------------------------------
# หน้าหลัก
# ---------------------------------------------------------------
func _build_main() -> void:
	# ชื่อเกม: ขอบเรืองสีส้มเต้นหายใจ
	var title := UiTheme.title(GameSettings.t("menu.title"), 76)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.add_theme_color_override("font_color", Color(1.0, 0.93, 0.82))
	title.add_theme_constant_override("outline_size", 14)
	title.add_theme_color_override("font_outline_color", Color(0.6, 0.15, 0.05, 0.9))
	_main_box.add_child(title)

	var tw := title.create_tween().set_loops()
	tw.tween_property(title, "theme_override_colors/font_outline_color", Color(1.0, 0.55, 0.15, 1.0), 1.6)
	tw.tween_property(title, "theme_override_colors/font_outline_color", Color(0.6, 0.15, 0.05, 0.9), 1.6)

	var tag := UiTheme.label(GameSettings.t("menu.tagline"), 20, Color(0.95, 0.75, 0.55, 0.9))
	_main_box.add_child(tag)

	var line := ColorRect.new()
	line.color = UiTheme.ACCENT
	line.custom_minimum_size = Vector2(140, 4)
	line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_main_box.add_child(line)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 18)
	_main_box.add_child(spacer)

	var buttons: Array[Button] = []
	buttons.append(UiTheme.button(GameSettings.t("menu.start"), _on_start))
	buttons.append(UiTheme.button(GameSettings.t("menu.settings"), _go.bind("settings")))
	buttons.append(UiTheme.button(GameSettings.t("menu.stats"), _go.bind("stats")))
	buttons.append(UiTheme.button(GameSettings.t("menu.quit"), _on_quit))
	for b in buttons:
		b.custom_minimum_size = BUTTON_SIZE
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_main_box.add_child(b)

	# สถิติสั้นๆ ด้านล่าง
	if GameStats.best_wave > 0:
		var spacer2 := Control.new()
		spacer2.custom_minimum_size = Vector2(0, 10)
		_main_box.add_child(spacer2)
		var best := UiTheme.label("%s: %d" % [GameSettings.t("stats.best_wave"), GameStats.best_wave], 18, Color(0.8, 0.8, 0.86, 0.85))
		_main_box.add_child(best)

	# ค่อยๆ ลอยขึ้นมาทีละอัน
	var i := 0
	for n in _main_box.get_children():
		if n is Control:
			(n as Control).modulate.a = 0.0
			var t := (n as Control).create_tween()
			t.tween_interval(0.15 + i * 0.07)
			t.tween_property(n, "modulate:a", 1.0, 0.4)
			i += 1

	buttons[0].grab_focus.call_deferred()

func _on_start() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)

func _on_quit() -> void:
	GameSettings.save()
	GameStats.save()
	get_tree().quit()

# ---------------------------------------------------------------
# ตั้งค่า
# ---------------------------------------------------------------
func _build_settings() -> void:
	var sp := SettingsPanel.new()
	sp.back_pressed.connect(_go.bind("main"))
	_content.add_child(sp)

# ---------------------------------------------------------------
# สถิติ
# ---------------------------------------------------------------
func _build_stats() -> void:
	_content.add_child(UiTheme.title(GameSettings.t("stats.page_title")))

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	rows.custom_minimum_size = Vector2(0, 250)
	_content.add_child(rows)

	rows.add_child(_stat_row(GameSettings.t("stats.kills"), str(GameStats.total_kills)))
	rows.add_child(_stat_row(GameSettings.t("stats.playtime"), _format_time(GameStats.total_play_time)))
	rows.add_child(_stat_row(GameSettings.t("stats.best_wave"), str(GameStats.best_wave)))
	rows.add_child(_stat_row(GameSettings.t("stats.best_run"), str(GameStats.best_run_kills)))
	rows.add_child(_stat_row(GameSettings.t("stats.games"), str(GameStats.games_played)))

	var back := UiTheme.button(GameSettings.t("set.back"), _go.bind("main"))
	_content.add_child(back)
	back.grab_focus.call_deferred()

func _stat_row(label_text: String, value_text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var l := UiTheme.label(label_text)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)

	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(190, 0)
	badge.add_theme_stylebox_override("panel", UiTheme.box(Color(0.14, 0.14, 0.17), Color(1, 1, 1, 0.15), 10))
	var v := UiTheme.label(value_text, 22, UiTheme.ACCENT)
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

# ---------------------------------------------------------------
# โชว์มอน 3D (ฝั่งขวา)
# ---------------------------------------------------------------
func _build_showcase() -> void:
	var cont := SubViewportContainer.new()
	cont.stretch = true
	cont.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cont)
	cont.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_showcase = cont

	_viewport = SubViewport.new()
	_viewport.own_world_3d = true          # โลก 3D แยกของตัวเอง ไม่ปนกับเกม
	_viewport.transparent_bg = true        # เห็นฉากหลังที่วาดไว้ทะลุออกมา
	_viewport.msaa_3d = Viewport.MSAA_4X
	cont.add_child(_viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.3, 0.42)
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_viewport.add_child(we)

	# พื้น (ให้มอนยืน ไม่ตกหาย)
	var floor_body := StaticBody3D.new()
	var floor_col := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(30.0, 1.0, 30.0)
	floor_col.shape = floor_shape
	floor_col.position.y = -0.5
	floor_body.add_child(floor_col)
	_viewport.add_child(floor_body)

	# เลือกมอน
	var kind := randi() % 4
	match kind:
		0:
			_enemy = EnemyMelee.new()
			_enemy_h = 1.9
		1:
			_enemy = EnemyRanged.new()
			_enemy_h = 2.0
		2:
			_enemy = EnemyAOE.new()
			_enemy_h = 2.5
		_:
			_enemy = EnemyBoss.new()
			_enemy_h = 4.3
	_enemy.position = Vector3(0.0, 0.05, 0.0)
	_enemy.rotation.y = PI   # หันหน้าเข้ากล้อง
	# เพิ่มแบบ deferred: _ready ของมอนจะหาผู้เล่นผ่าน current_scene ต้องรอให้ฉากเมนูตั้งเสร็จก่อน
	_viewport.add_child.call_deferred(_enemy)

	# แท่นใต้เท้า + วงแสงสีเดียวกับตัวมอน
	var plat_r := maxf(1.8, _enemy_h * 0.55)
	var plat := MeshInstance3D.new()
	var plat_mesh := CylinderMesh.new()
	plat_mesh.top_radius = plat_r
	plat_mesh.bottom_radius = plat_r * 1.05
	plat_mesh.height = 0.1
	var plat_mat := StandardMaterial3D.new()
	plat_mat.albedo_color = Color(0.08, 0.07, 0.09)
	plat_mat.metallic = 0.5
	plat_mat.roughness = 0.5
	plat_mesh.material = plat_mat
	plat.mesh = plat_mesh
	plat.position.y = -0.05
	_viewport.add_child(plat)

	var ring := MeshInstance3D.new()
	var ring_mesh := CylinderMesh.new()
	ring_mesh.top_radius = plat_r * 0.92
	ring_mesh.bottom_radius = plat_r * 0.92
	ring_mesh.height = 0.02
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(_enemy.glow_color, 0.35)
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mesh.material = ring_mat
	ring.mesh = ring_mesh
	ring.position.y = 0.01
	_viewport.add_child(ring)

	# แสง: แสงหลักอุ่น + แสงขอบสีเดียวกับตัวมอนจากด้านหลัง
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30.0, 40.0, 0.0)
	key.light_color = Color(1.0, 0.75, 0.6)
	key.light_energy = 1.3
	key.shadow_enabled = true
	_viewport.add_child(key)

	var rim := OmniLight3D.new()
	rim.position = Vector3(-3.0, _enemy_h * 1.1, -2.5)
	rim.light_color = _enemy.glow_color
	rim.light_energy = 4.0
	rim.omni_range = 14.0
	_viewport.add_child(rim)

	var fill := OmniLight3D.new()
	fill.position = Vector3(3.0, _enemy_h * 0.6, 4.0)
	fill.light_color = Color(0.55, 0.45, 0.8)
	fill.light_energy = 1.2
	fill.omni_range = 14.0
	_viewport.add_child(fill)

	_cam = Camera3D.new()
	_cam.fov = 40.0
	_cam.current = true
	_viewport.add_child(_cam)

func _process(delta: float) -> void:
	if _enemy == null or _cam == null or not _showcase.visible:
		return
	_t += delta

	var sz := get_viewport_rect().size
	if sz.x > 0.0 and sz.y > 0.0:
		var m := get_viewport().get_mouse_position() / sz - Vector2(0.5, 0.5)
		_m = _m.lerp(m.clamp(Vector2(-0.5, -0.5), Vector2(0.5, 0.5)), 1.0 - exp(-4.0 * delta))

	# มอนหมุนตัวช้าๆ + ตามเมาส์เล็กน้อย
	_enemy.rotation.y = PI + sin(_t * 0.5) * 0.35 + _m.x * 0.7

	# วางกล้องให้มอนอยู่ราว 70% ของจอทางขวา (ไม่ต้องเอียงกล้อง ภาพจึงไม่เบี้ยว)
	var vp := Vector2(_viewport.size)
	var aspect := vp.x / maxf(vp.y, 1.0)
	var dist := _enemy_h * 2.3
	var half_w := dist * tan(deg_to_rad(_cam.fov * 0.5)) * aspect
	_cam.position = Vector3(-half_w * 0.42 + _m.x * 0.25, _enemy_h * 0.52 + _m.y * -0.15, dist)

# ให้มอนทำท่าง้างโจมตีเป็นระยะ (ท่าเดียวกับตอนสู้จริง)
func _pose_enemy() -> void:
	if _enemy == null or not is_instance_valid(_enemy) or not _showcase.visible:
		return
	_enemy._telegraph(_enemy.glow_color.lerp(Color.WHITE, 0.25), 1.4)

class_name IntroCutscene
extends Node

# คัทซีนเปิดเกม สร้างจากโค้ดล้วน (WaveManager สร้างให้และรอจนจบก่อนนับถอยหลัง Wave 1)
# ไม่ต้องแก้ wave_manager.gd: ยังใช้ start(player) และ signal finished เหมือนเดิม
#
# ลำดับ:
#   SPACE       อวกาศ ดาวเคราะห์สีซีดๆ (โลกที่ไม่เขียวแล้ว) กระสวยบินออกไปพุ่งเข้าดาว
#               ลุกเป็นลูกไฟตอนเข้าบรรยากาศ แล้วแฟลชขาวตัดเข้าแมพ
#               (ฉากนี้อยู่ใน SubViewport โลก 3D แยก ไม่ปนกับแมพเกม)
#   FLIGHT      ตัดมาที่แมพเกม กล้องตั้งบนพื้น กระสวยไฟลุกดิ่งลงมาจากฟ้า เครื่องยนต์ติดๆ ดับๆ
#   SKID        กระแทกพื้น ฝุ่นระเบิด ประกายไฟ ไถลเป็นร่องดินจนหยุด กล้องสั่นแรง
#   HOLD        ฝุ่นจาง ควันลอยจากเครื่องยนต์ กล้องเลื่อนเข้าหาเบาๆ
#   TO_INTERIOR เฟดดำสั้นๆ ตัดเข้าห้องกระสวยด้วยมุมมองผู้เล่น ปืนยกขึ้นมาในมือ
#   DOOR        ประตูท้ายค่อยๆ ลดลงเป็นทางลาด แสงภายนอกสาดเข้ามา
#   WALK        ผู้เล่นเดินออกมา (ใช้ระบบเดินจริงของ player.gd)
#   FADE_OUT    เฟดดำ ปล่อยการควบคุมคืนผู้เล่น
#   FADE_IN     เฟดสว่างเข้าสู่เกม
# กด Space เพื่อข้าม
#
# ระหว่างคัทซีน: ซ่อน HUD ทั้งหมด, ปิดการหันเมาส์/ยิง, WaveManager ล็อกเมนูหยุดเกม
# กระสวยค้างอยู่ในฉากหลังคัทซีน (มี collision เป็นสิ่งกีดขวาง มีควันลอยจากเครื่องยนต์ตลอด)
# ร่องดินที่กระสวยไถไว้ก็ค้างอยู่บนพื้นเช่นกัน

signal finished

enum S { SPACE, FLIGHT, SKID, HOLD, TO_INTERIOR, DOOR, WALK, FADE_OUT, FADE_IN, DONE }

# --- ฉากอวกาศ (กล้องอยู่ที่ 0,0,0 ของโลก SubViewport) ---
const PLANET_R := 2400.0
const PLANET_CENTER := Vector3(420.0, -2150.0, -3700.0)
const SUN_DIR := Vector3(0.75, 0.55, 0.45)        # ทิศที่ดวงอาทิตย์อยู่
const SPACE_START := Vector3(-16.0, 7.0, -85.0)   # ตำแหน่งกระสวยตอนเริ่ม
const SPACE_SHUTTLE_SCALE := 1.5                  # ขยายกระสวยในฉากอวกาศให้เห็นชัด

# --- พิกัดโลกของแมพเกม (ผู้เล่นเริ่มที่ (0,1,0) หันไป -Z) ---
const START_Y := 85.0                           # กระสวยเริ่มสูงเท่านี้
const START_Z := -260.0                         # และไกลเท่านี้
const IMPACT_Z := -34.0                         # จุดที่ท้ายกระสวยกระแทกพื้นครั้งแรก
const LAND_Z := 4.0                             # ท้ายกระสวยตอนหยุดนิ่ง (กระสวยยาวไปทาง +Z)
const SHUTTLE_LEN := 19.5
const START_POS := Vector3(0.0, 1.0, 10.0)      # ที่ยืนของผู้เล่นในห้องกระสวย
const WALK_END_Z := -5.0                        # เดินออกมาถึงตรงนี้แล้วจบ
const CAM_POS := Vector3(-15.0, 1.6, 42.0)      # กล้องฉากบนพื้น

# --- เวลา (วินาที) ---
const SPACE_T := 8.5
const FLIGHT_T := 5.2
const SKID_T := 1.9
const HOLD_T := 2.4
const DOOR_T := 2.4
const FADE_OUT_T := 0.55
const FADE_IN_T := 0.9

const BAR_RATIO := 0.11
const SHUTTLE_GLOW := Color(0.12, 1.0, 0.62)    # โทนเดียวกับปืนของผู้เล่น
const HOT := Color(1.0, 0.82, 0.62)             # สีแฟลชร้อนตอนเข้าบรรยากาศ / กระแทก
const REAR_LEN := 7.0
const BELLY_LEN := 4.5

const SKIP_TEXT := {"en": "PRESS SPACE TO SKIP", "th": "กด SPACE เพื่อข้าม"}

# ---------------------------------------------------------------
# Shader (ฉากอวกาศ)
# ---------------------------------------------------------------
const NOISE_GLSL := """
float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 hash33(vec3 p3) {
	p3 = fract(p3 * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.xxy + p3.yxx) * p3.zyx);
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(hash13(i), hash13(i + vec3(1.0, 0.0, 0.0)), f.x);
	float b = mix(hash13(i + vec3(0.0, 1.0, 0.0)), hash13(i + vec3(1.0, 1.0, 0.0)), f.x);
	float c = mix(hash13(i + vec3(0.0, 0.0, 1.0)), hash13(i + vec3(1.0, 0.0, 1.0)), f.x);
	float d = mix(hash13(i + vec3(0.0, 1.0, 1.0)), hash13(i + vec3(1.0, 1.0, 1.0)), f.x);
	return mix(mix(a, b, f.y), mix(c, d, f.y), f.z);
}

float fbm(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 6; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return s;
}
"""

# ท้องฟ้าดาว + แถบทางช้างเผือกจางๆ
const STAR_SKY_BODY := """
uniform vec3 haze_color : source_color = vec3(0.10, 0.07, 0.13);

vec3 stars(vec3 dir, float scale, float density, float size, float bright) {
	vec3 p = dir * scale;
	vec3 id = floor(p);
	vec3 f = fract(p);
	float h = hash13(id);
	if (h > density) {
		return vec3(0.0);
	}
	vec3 c = hash33(id) * 0.64 + 0.18;
	float d = length(f - c);
	float k = max(1.0 - d / size, 0.0);
	float b = k * k;
	float m = hash13(id + 17.0);
	vec3 tint = mix(vec3(0.65, 0.78, 1.0), vec3(1.0, 0.82, 0.62), hash13(id + 5.0));
	return tint * b * bright * (0.3 + 0.7 * m);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 col = vec3(0.003, 0.004, 0.009);
	vec3 bn = normalize(vec3(0.3, 0.85, 0.4));
	float t = dot(dir, bn) * 3.5;
	float band = exp(-t * t);
	float cl = vnoise(dir * 5.0) * 0.6 + vnoise(dir * 13.0) * 0.4;
	col += haze_color * band * (0.2 + cl);
	col += stars(dir, 55.0, 0.10, 0.20, 1.6);
	col += stars(dir, 120.0, 0.12, 0.18, 1.2);
	col += stars(dir, 28.0, 0.05, 0.28, 2.6);
	COLOR = col;
}
"""

# โลกที่ตายแล้ว: ทะเลหม่นเทา แผ่นดินซีดสีฝุ่น รอยไหม้ดำ น้ำแข็งขั้วโลกขุ่น เมฆเหลืองหม่น
# ฝั่งกลางคืนมีไฟป่าที่ยังไม่มอดส้มจางๆ
const PLANET_BODY := """
uniform vec3 sun_dir = vec3(0.75, 0.55, 0.45);
varying vec3 v_obj;
varying vec3 v_wn;

void vertex() {
	v_obj = VERTEX;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(v_obj);
	float c = fbm(n * 2.4 + vec3(3.1, 1.7, 5.3));
	float det = fbm(n * 16.0 + 7.0);
	float land = smoothstep(0.50, 0.545, c);

	vec3 sea = mix(vec3(0.17, 0.20, 0.23), vec3(0.30, 0.31, 0.29), smoothstep(0.38, 0.50, c));
	vec3 ground = mix(vec3(0.33, 0.30, 0.28), vec3(0.68, 0.60, 0.47), smoothstep(0.30, 0.75, det));
	float scar = smoothstep(0.58, 0.72, fbm(n * 5.5 + 11.0));
	ground = mix(ground, vec3(0.13, 0.10, 0.09), scar * 0.85);
	vec3 surf = mix(sea, ground, land);

	float lat = abs(n.y) + (det - 0.5) * 0.12;
	surf = mix(surf, vec3(0.74, 0.75, 0.77), smoothstep(0.82, 0.93, lat));

	vec3 warp = vec3(fbm(n * 3.0 + 2.0), fbm(n * 3.0 + 9.0), 0.0) * 0.8;
	float cl = fbm(n * 3.6 + warp + vec3(TIME * 0.003, 0.0, 0.0));
	float cloud = smoothstep(0.50, 0.78, cl);
	surf = mix(surf, vec3(0.62, 0.58, 0.52), cloud * 0.7);

	float ndl = dot(normalize(v_wn), normalize(sun_dir));
	float night = 1.0 - smoothstep(-0.25, 0.02, ndl);
	float fire = smoothstep(0.70, 0.78, fbm(n * 9.0 + 4.0)) * land * (1.0 - cloud * 0.6);

	ALBEDO = surf;
	ROUGHNESS = 0.95;
	METALLIC = 0.0;
	EMISSION = vec3(1.0, 0.42, 0.1) * fire * night * 1.6;
}
"""

# ชั้นบรรยากาศ: เรืองขอบดาว (เฉพาะด้านที่โดนแสง)
const ATMO_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;

uniform vec3 sun_dir = vec3(0.75, 0.55, 0.45);
uniform vec3 tint : source_color = vec3(0.80, 0.56, 0.38);
uniform float strength = 1.3;
varying vec3 v_wn;

void vertex() {
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	float lit = clamp(dot(v_wn, normalize(sun_dir)) * 0.9 + 0.3, 0.0, 1.0);
	ALBEDO = tint * strength;
	ALPHA = clamp(fres * lit, 0.0, 1.0);
}
"""

# ชุดชิ้นส่วนของกระสวยหนึ่งลำ (ฉากอวกาศกับฉากบนพื้นสร้างแยกกันคนละลำ)
class ShuttleRig extends RefCounted:
	var root: Node3D
	var door: Node3D
	var bay_light: OmniLight3D
	var glow_light: OmniLight3D
	var heat: MeshInstance3D
	var heat_mat: StandardMaterial3D
	var flames_rear: Array[Node3D] = []
	var flames_belly: Array[Node3D] = []
	var trails: Array[GPUParticles3D] = []

var _player: CharacterBody3D
var _gun: Camera3D
var _vm: Node3D

var _state := S.SPACE
var _st := 0.0
var _t := 0.0
var _skipped := false
var _impacted := false
var _thump := 0.0
var _shake := 0.0
var _cam_push := 0.0
var _entry := 0.0
var _fade_a := 1.0
var _fade_col := Color.BLACK
var _bars := 0.0

# ฉากอวกาศ
var _sv_box: SubViewportContainer
var _sv: SubViewport
var _space_cam: Camera3D
var _planet: MeshInstance3D
var _space: ShuttleRig
var _entry_quad: MeshInstance3D
var _entry_mat: StandardMaterial3D
var _space_goal := Vector3.ZERO

# ฉากบนพื้น
var _cam: Camera3D
var _ground: ShuttleRig
var _dust_burst: GPUParticles3D
var _dust_trail: GPUParticles3D
var _sparks: GPUParticles3D
var _smoke: Array[GPUParticles3D] = []
var _furrow: MeshInstance3D

var _hidden_layers: Array[CanvasLayer] = []
var _ui_layer: CanvasLayer
var _fade_rect: ColorRect
var _bar_top: ColorRect
var _bar_bot: ColorRect
var _skip_label: Label

# ===================================================================
# เริ่มคัทซีน
# ===================================================================
func start(_player_node: Node3D) -> void:
	set_process(false)   # รอ _begin() สร้างฉากเสร็จก่อน

	_player = _player_node as CharacterBody3D
	_gun = _player.get("camera") as Camera3D
	_vm = _gun.get_node_or_null("Viewmodel") as Node3D

	# ซ่อน HUD ทั้งหมดที่มีอยู่ (ก่อนสร้าง UI ของคัทซีนเอง)
	for l in get_tree().current_scene.find_children("*", "CanvasLayer", true, false):
		var layer := l as CanvasLayer
		if layer != null and layer.visible:
			layer.visible = false
			_hidden_layers.append(layer)

	# ปิดการควบคุมผู้เล่น (เดินยังทำงาน เพราะต้องใช้ตอนเดินออกจากกระสวย)
	_player.set_process_unhandled_input(false)   # ไม่หันเมาส์
	_gun.set_process(false)                      # ไม่ยิง / รีโหลด
	if _vm != null:
		_vm.visible = false                      # ปืนลอยอยู่กลางลานจะเห็นจากกล้องคัทซีน

	_reserve_lane()   # ต้องทำก่อน MapBuilder.build() ที่ถูกเรียกแบบ deferred
	_build_ui()
	_update_ui()      # เฟรมแรกเป็นสีดำทันที

	# add_child ให้ฉากหลักตอน _ready ของ WaveManager ยังไม่ได้ (ฉากกำลังตั้งค่า) จึงสร้างแบบ deferred
	_begin.call_deferred()

func _begin() -> void:
	_build_space()
	_build_ground()

	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.far = 3000.0
	add_child(_cam)
	_cam.position = CAM_POS
	_cam.make_current()

	_pose_space(0.0)
	_update_space_cam(0.0)
	_pose_flight(0.0)
	_update_cam()
	set_process(true)

# กันพื้นที่ร่องไถของกระสวย ไม่ให้ของตกแต่งแมพไปอยู่ขวางทาง (ผ่าน MapBuilder ของ WaveManager)
func _reserve_lane() -> void:
	var wm := get_parent()
	if wm == null:
		return
	var map: Variant = wm.get("_map")
	if map != null and map.has_method("reserve"):
		for z in [-30.0, -18.0, -6.0]:
			map.reserve(Vector2(0.0, z), 11.0)

func _input(event: InputEvent) -> void:
	if _state == S.DONE:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode != KEY_SPACE and key.physical_keycode != KEY_SPACE:
		return
	# กัน Space ไปสั่งให้ตัวละครกระโดดระหว่างคัทซีน
	if InputMap.has_action("jump"):
		Input.action_release("jump")
	if _state >= S.FADE_OUT or _t < 0.5:
		return
	get_viewport().set_input_as_handled()
	_skip()

func _skip() -> void:
	Input.action_release("move_forward")
	_skipped = true
	_fade_col = Color.BLACK
	_st = clampf(_fade_a, 0.0, 1.0) * FADE_OUT_T
	_state = S.FADE_OUT

func _enter(s: S) -> void:
	_state = s
	_st = 0.0
	if s >= S.TO_INTERIOR:
		_fade_col = Color.BLACK

# ===================================================================
# Timeline
# ===================================================================
func _process(delta: float) -> void:
	delta = minf(delta, 0.05)   # กันเฟรมกระตุกตอนโหลด ทำให้ไทม์ไลน์ข้ามช็อต
	_t += delta
	_st += delta
	_thump *= exp(-3.0 * delta)

	match _state:
		S.SPACE: _tick_space()
		S.FLIGHT: _tick_flight()
		S.SKID: _tick_skid()
		S.HOLD: _tick_hold()
		S.TO_INTERIOR: _tick_to_interior()
		S.DOOR: _tick_door()
		S.WALK: _tick_walk()
		S.FADE_OUT: _tick_fade_out()
		S.FADE_IN: _tick_fade_in()

	if _state < S.FADE_IN:
		_bars = minf(_t / 0.8, 1.0)
	_update_ui()

func _tick_space() -> void:
	var u := clampf(_st / SPACE_T, 0.0, 1.0)
	if is_instance_valid(_planet):
		_planet.rotation.y = _t * 0.012
	_pose_space(u)
	_update_space_cam(u)

	# เฟดจากดำตอนเริ่ม / แฟลชร้อนตอนท้ายก่อนตัดเข้าแมพ
	var fin := 1.0 - clampf(_st / 1.2, 0.0, 1.0)
	var w := smoothstep(0.90, 1.0, u)
	if w > 0.0:
		_fade_col = HOT
		_fade_a = w
	else:
		_fade_col = Color.BLACK
		_fade_a = fin

	if u >= 1.0:
		_begin_ground()

func _begin_ground() -> void:
	_close_space()
	_fade_col = HOT
	_fade_a = 1.0
	_set_trails(_ground, true)
	_enter(S.FLIGHT)

func _tick_flight() -> void:
	var u := clampf(_st / FLIGHT_T, 0.0, 1.0)
	_fade_col = HOT
	_fade_a = 1.0 - clampf(_st / 0.8, 0.0, 1.0)
	_pose_flight(u)
	_shake = smoothstep(0.3, 1.0, u) * 0.05
	_update_cam()
	if u >= 1.0:
		_impact()
		_enter(S.SKID)

func _tick_skid() -> void:
	var tt := _st
	var k := clampf(tt / SKID_T, 0.0, 1.0)
	var e := 1.0 - (1.0 - k) * (1.0 - k)
	var z := lerpf(IMPACT_Z, LAND_Z, e)

	# ท้ายกระแทกก่อน แล้วหัวกระแทกตาม โยกคืนตัวจนนิ่ง
	var pitch := -0.10 * exp(-3.0 * tt) * cos(9.0 * tt)
	var y := maxf(sin(pitch), 0.0) * SHUTTLE_LEN
	var roll := sin(tt * 7.0) * 0.035 * exp(-2.0 * tt)
	var yaw := sin(tt * 3.5) * 0.02 * (1.0 - k)
	_ground.root.position = Vector3(0.0, y, z)
	_ground.root.rotation = Vector3(pitch, yaw, roll)
	_set_furrow(z)

	# ฝุ่นลากยาว + ประกายไฟ ตอนไถ
	_dust_trail.emitting = k < 0.8
	_sparks.emitting = k < 0.7

	# เครื่องยนต์ดับ ความร้อนจาง ไฟกระสวยหรี่
	_set_flames(_ground, 0.4 * exp(-6.0 * tt), 0.0)
	_ground.heat_mat.albedo_color.a = 0.4 * (1.0 - k)
	_ground.glow_light.light_energy = 4.0 * (1.0 - k)

	# แฟลชตอนกระแทก
	_fade_col = HOT
	_fade_a = 0.5 * exp(-8.0 * tt)

	_shake = 0.35 * (1.0 - k)
	_update_cam()
	if k >= 1.0:
		_enter(S.HOLD)

func _tick_hold() -> void:
	var k := clampf(_st / HOLD_T, 0.0, 1.0)
	_ground.root.position = Vector3(0.0, 0.0, LAND_Z)
	_ground.root.rotation = Vector3.ZERO
	_set_flames(_ground, 0.0, 0.0)
	_ground.heat.visible = false
	_ground.glow_light.light_energy = 1.0 * (1.0 - k)
	_dust_trail.emitting = false
	_sparks.emitting = false
	_set_trails(_ground, false)
	_shake = 0.05 * (1.0 - k)
	_cam_push = k
	_fade_a = 0.0
	_update_cam()
	if _st >= HOLD_T:
		_enter(S.TO_INTERIOR)

func _tick_to_interior() -> void:
	_fade_a = clampf(_st / 0.4, 0.0, 1.0)
	_update_cam()
	if _fade_a >= 1.0:
		_switch_to_interior()
		_enter(S.DOOR)

func _tick_door() -> void:
	_fade_a = 1.0 - clampf(_st / 0.5, 0.0, 1.0)
	var k := smoothstep(0.0, 1.0, clampf((_st - 0.9) / 1.3, 0.0, 1.0))
	_ground.door.rotation.x = deg_to_rad(-90.0) * k
	# ไฟในห้องกระพริบเหมือนระบบเสียหายจากการตก
	_ground.bay_light.light_energy = (1.6 + 0.35 * sin(_t * 23.0) * sin(_t * 7.0)) * (0.7 + 0.3 * sin(_t * 37.0))
	if _st >= DOOR_T:
		Input.action_press("move_forward")   # ใช้ระบบเดินจริง
		_enter(S.WALK)

func _tick_walk() -> void:
	if _player.global_position.z <= WALK_END_Z or _st > 4.5:
		Input.action_release("move_forward")
		_enter(S.FADE_OUT)

func _tick_fade_out() -> void:
	_fade_a = clampf(_st / FADE_OUT_T, 0.0, 1.0)
	if _fade_a >= 1.0:
		_finalize()
		_enter(S.FADE_IN)

func _tick_fade_in() -> void:
	var k := clampf(_st / FADE_IN_T, 0.0, 1.0)
	_fade_a = 1.0 - k
	_bars = 1.0 - k
	if _st >= FADE_IN_T:
		_state = S.DONE
		set_process(false)
		queue_free()   # กระสวยอยู่ในฉากหลัก จึงไม่หายไปด้วย

# ===================================================================
# ท่าของกระสวย / กล้อง : ฉากอวกาศ
# ===================================================================
func _pose_space(u: float) -> void:
	# ช้าตอนเริ่ม เร่งกลางทาง ชะลอตอนเสียดสีกับบรรยากาศ
	var s := u * u * (3.0 - 2.0 * u)
	var pos := SPACE_START.lerp(_space_goal, s)
	var dir := (_space_goal - SPACE_START).normalized()
	var roll := sin(_t * 0.8) * 0.06

	var root := _space.root
	root.basis = Basis.looking_at(-dir, Vector3.UP) * Basis(Vector3(0.0, 0.0, 1.0), roll)
	root.scale = Vector3.ONE * SPACE_SHUTTLE_SCALE
	root.position = pos

	# เข้าชั้นบรรยากาศ: เปลวความร้อน + ลูกไฟใหญ่ขึ้นเรื่อยๆ
	var d := pos.distance_to(PLANET_CENTER)
	_entry = clampf((PLANET_R * 1.08 - d) / (PLANET_R * 0.12), 0.0, 1.0)
	_space.heat_mat.albedo_color.a = 0.6 * _entry
	_space.heat.visible = _entry > 0.02
	_entry_mat.albedo_color.a = _entry
	var gs := 6.0 + 140.0 * _entry
	_entry_quad.scale = Vector3(gs, gs, gs)
	_entry_quad.visible = _entry > 0.01

	_set_flames(_space, 1.1 + 0.3 * _entry, 0.0)
	_space.glow_light.light_energy = 1.0 + 6.0 * _entry

func _update_space_cam(u: float) -> void:
	var focus := Vector3(40.0, -230.0, -1100.0)
	var aim := focus.lerp(_space.root.position, 0.55)
	var shake := Vector3(sin(_t * 61.0), cos(_t * 57.0), 0.0) * 0.18 * _entry
	_space_cam.position = Vector3(sin(_t * 0.4) * 1.5, 1.0 + cos(_t * 0.3) * 0.8, -u * 40.0) + shake
	_space_cam.look_at(aim, Vector3.UP)

# ===================================================================
# ท่าของกระสวย / กล้อง : ฉากบนพื้น
# ===================================================================
func _flight_pos(u: float) -> Vector3:
	var z := lerpf(START_Z, IMPACT_Z, 0.5 * u + 0.5 * u * u)   # เร่งเข้าหาพื้น
	var y := START_Y * pow(1.0 - u, 1.5)
	return Vector3(0.0, y, z)

func _pose_flight(u: float) -> void:
	var p := _flight_pos(u)
	var a := _flight_pos(maxf(u - 0.02, 0.0))
	var b := _flight_pos(minf(u + 0.02, 1.0))
	var path_ang := atan2(a.y - b.y, b.z - a.z)   # มุมทิ่มตามแนวบิน
	var flare := smoothstep(0.80, 1.0, u)
	var pitch := lerpf(path_ang, -0.10, flare)     # ท้ายๆ เชิดหัวขึ้นนิด ให้ท้ายลงก่อน
	var roll := sin(_t * 2.1) * 0.05 * (1.0 - u) + sin(_t * 9.0) * 0.015 * u
	_ground.root.position = p
	_ground.root.rotation = Vector3(pitch, 0.0, roll)

	# เครื่องยนต์ติดๆ ดับๆ ช่วงท้าย
	var sputter := 1.0 - smoothstep(0.55, 0.95, u) * (0.45 + 0.45 * sin(_t * 33.0) * sin(_t * 13.0))
	_set_flames(_ground, 1.15 * sputter, 0.7 * smoothstep(0.55, 0.75, u) * sputter)
	_ground.glow_light.light_energy = 2.0 + 6.0 * (1.0 - 0.5 * u)

	# ทั้งลำลุกเป็นไฟ
	_ground.heat_mat.albedo_color.a = 0.55 * (1.0 - 0.5 * u)
	_ground.heat.visible = true

func _update_cam() -> void:
	var a := _shake + _thump * 0.45
	var sh := Vector3(sin(_t * 47.0), cos(_t * 53.0), sin(_t * 39.0) * 0.5) * a
	_cam.position = CAM_POS + sh
	_cam.fov = 55.0 - _cam_push * 8.0
	_cam.look_at(_ground.root.to_global(Vector3(0.0, 2.5, 9.0)), Vector3.UP)
	_cam.rotate_object_local(Vector3.FORWARD, sin(_t * 41.0) * a * 0.03)

func _set_flames(rig: ShuttleRig, rear: float, belly: float) -> void:
	var fl := 0.92 + 0.08 * sin(_t * 40.0)
	for f in rig.flames_rear:
		f.visible = rear > 0.03
		f.scale = Vector3(fl, maxf(rear, 0.001) * fl, fl)
	for f in rig.flames_belly:
		f.visible = belly > 0.03
		f.scale = Vector3(fl, maxf(belly, 0.001) * fl, fl)

func _set_trails(rig: ShuttleRig, on: bool) -> void:
	for p in rig.trails:
		p.emitting = on

func _set_smoke(on: bool) -> void:
	for s in _smoke:
		s.emitting = on

# กระแทกพื้น: ฝุ่นระเบิด วงคลื่นกระแทก แฟลชแสง ประกายไฟ ควัน กล้องสะเทือน
func _impact() -> void:
	_impacted = true
	_thump = 1.0
	_set_trails(_ground, false)   # หางไฟบนฟ้าหยุดปล่อย (ที่ปล่อยไปแล้วยังลอยค้างอยู่)
	_ensure_furrow()
	_set_smoke(true)

	if is_instance_valid(_dust_burst):
		_dust_burst.global_position = Vector3(0.0, 0.6, IMPACT_Z + 7.0)
		_dust_burst.restart()
		_dust_burst.emitting = true
		get_tree().create_timer(7.0).timeout.connect(_dust_burst.queue_free)   # ลบหลังฝุ่นจางหมด

	var scene := get_tree().current_scene

	var ring := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 1.0
	rm.bottom_radius = 1.0
	rm.height = 0.06
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(1.0, 0.85, 0.65, 0.5)
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.material = rmat
	ring.mesh = rm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(ring)
	ring.global_position = Vector3(0.0, 0.12, IMPACT_Z + 8.0)
	var tw := ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(24.0, 1.0, 24.0), 1.5) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(rmat, "albedo_color:a", 0.0, 1.5)
	tw.chain().tween_callback(ring.queue_free)

	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.7, 0.4)
	flash.light_energy = 14.0
	flash.omni_range = 50.0
	scene.add_child(flash)
	flash.global_position = Vector3(0.0, 2.5, IMPACT_Z + 8.0)
	var ft := flash.create_tween()
	ft.tween_property(flash, "light_energy", 0.0, 1.0)
	ft.tween_callback(flash.queue_free)

# ร่องดินที่กระสวยไถไว้ (ค้างอยู่บนพื้นหลังคัทซีน)
func _ensure_furrow() -> void:
	if is_instance_valid(_furrow):
		return
	var bm := BoxMesh.new()
	bm.size = Vector3(6.4, 0.03, 1.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.09, 0.065, 0.05)
	mat.roughness = 1.0
	bm.material = mat
	_furrow = MeshInstance3D.new()
	_furrow.mesh = bm
	_furrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(_furrow)
	_set_furrow(IMPACT_Z)

func _set_furrow(shuttle_z: float) -> void:
	if not is_instance_valid(_furrow):
		return
	var length := maxf(shuttle_z - IMPACT_Z + 4.0, 0.1)
	_furrow.scale = Vector3(1.0, 1.0, length)
	_furrow.position = Vector3(0.0, 0.025, IMPACT_Z + length * 0.5)

# ตัดเข้าไปในห้องกระสวย ด้วยมุมมองผู้เล่น
func _switch_to_interior() -> void:
	_player.global_position = START_POS
	_player.velocity = Vector3.ZERO
	_player.rotation = Vector3.ZERO
	var head := _player.get("head") as Node3D
	if head != null:
		head.rotation.x = 0.0
	_gun.make_current()
	_set_trails(_ground, false)
	_dust_trail.emitting = false
	_sparks.emitting = false
	if _vm != null:
		_vm.visible = true
		_vm.set("_equip", 0.0)   # ให้ปืนยกขึ้นมาในมือใหม่ (ท่าเดียวกับตอนเริ่มเกม)

# จบคัทซีน: จัดทุกอย่างเข้าสถานะพร้อมเล่น (ใช้ทั้งกรณีเล่นจบและกดข้าม)
func _finalize() -> void:
	Input.action_release("move_forward")
	_close_space()   # กดข้ามระหว่างฉากอวกาศ ฉากนั้นยังเปิดอยู่

	# กระสวยอยู่ในท่าจอดสมบูรณ์ ประตูเปิด
	_ground.root.position = Vector3(0.0, 0.0, LAND_Z)
	_ground.root.rotation = Vector3.ZERO
	_ground.door.rotation.x = deg_to_rad(-90.0)
	_set_flames(_ground, 0.0, 0.0)
	_set_trails(_ground, false)
	_ground.heat.visible = false
	_ground.glow_light.visible = false
	_ground.bay_light.light_energy = 1.0

	# ร่องดิน + ควัน (ถ้ากดข้ามก่อนกระแทก ก็ใส่ให้ครบเหมือนกัน)
	_ensure_furrow()
	_set_furrow(LAND_Z)
	_set_smoke(true)
	for p in [_dust_trail, _sparks]:
		if is_instance_valid(p):
			p.queue_free()
	if not _impacted and is_instance_valid(_dust_burst):
		_dust_burst.queue_free()   # ยังไม่เคยถูกใช้

	# ชนกำแพงกระสวยได้ (ผู้เล่นอยู่นอกตัวกระสวยแล้ว)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(7.0, 4.4, 16.0)
	cs.shape = bs
	cs.position = Vector3(0.0, 2.2, 8.0)
	body.add_child(cs)
	_ground.root.add_child(body)

	# ผู้เล่น
	if _skipped:
		_player.global_position = Vector3(0.0, 1.0, WALK_END_Z)
		_player.velocity = Vector3.ZERO
	_player.rotation = Vector3.ZERO
	var head := _player.get("head") as Node3D
	if head != null:
		head.rotation.x = 0.0
	if _vm != null:
		_vm.visible = true
	_gun.make_current()
	_gun.set_process(true)
	_player.set_process_unhandled_input(true)
	if is_instance_valid(_cam):
		_cam.queue_free()

	for l in _hidden_layers:
		if is_instance_valid(l):
			l.visible = true

	finished.emit()

func _close_space() -> void:
	if is_instance_valid(_sv_box):
		_sv_box.queue_free()   # โลก 3D ในนั้น (ดาว กระสวยอวกาศ) ถูกลบพร้อมกัน
	_sv_box = null
	_space = null

# ===================================================================
# UI ของคัทซีน (แถบดำบนล่าง + เฟด + ข้อความข้าม)
# ===================================================================
func _build_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 50
	add_child(_ui_layer)

	_bar_top = ColorRect.new()
	_bar_top.color = Color.BLACK
	_bar_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_layer.add_child(_bar_top)

	_bar_bot = ColorRect.new()
	_bar_bot.color = Color.BLACK
	_bar_bot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_layer.add_child(_bar_bot)

	GameSettings.ensure_loaded()
	var skip_txt: String = SKIP_TEXT.get(GameSettings.language, SKIP_TEXT["en"])
	_skip_label = Label.new()
	_skip_label.text = skip_txt
	_skip_label.add_theme_font_size_override("font_size", 18)
	_skip_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	_skip_label.add_theme_constant_override("outline_size", 4)
	_skip_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_skip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_skip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_layer.add_child(_skip_label)

	_fade_rect = ColorRect.new()
	_fade_rect.color = Color.BLACK
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_layer.add_child(_fade_rect)

func _update_ui() -> void:
	var vp := get_viewport().get_visible_rect().size
	var bh := vp.y * BAR_RATIO * _bars
	_bar_top.position = Vector2.ZERO
	_bar_top.size = Vector2(vp.x, bh)
	_bar_bot.position = Vector2(0.0, vp.y - bh)
	_bar_bot.size = Vector2(vp.x, bh)

	_fade_rect.position = Vector2.ZERO
	_fade_rect.size = vp
	_fade_rect.color = Color(_fade_col.r, _fade_col.g, _fade_col.b, _fade_a)

	_skip_label.size = Vector2(500.0, 30.0)
	_skip_label.position = Vector2(vp.x - 530.0, vp.y - bh - 44.0)
	var a := clampf((_t - 1.0) / 0.6, 0.0, 1.0) * (0.55 + 0.45 * sin(_t * 3.0))
	_skip_label.modulate.a = a if _state < S.FADE_OUT else 0.0

# ===================================================================
# ฉากอวกาศ (SubViewport โลก 3D แยก)
# ===================================================================
func _build_space() -> void:
	_sv_box = SubViewportContainer.new()
	_sv_box.stretch = true
	_sv_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_layer.add_child(_sv_box)
	_ui_layer.move_child(_sv_box, 0)   # อยู่ใต้แถบดำ / เฟด / ข้อความข้าม
	_sv_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_sv = SubViewport.new()
	_sv.own_world_3d = true
	_sv.msaa_3d = Viewport.MSAA_4X
	_sv_box.add_child(_sv)

	# ท้องฟ้าดาว + เรืองแสง
	var sky_shader := Shader.new()
	sky_shader.code = "shader_type sky;\n" + NOISE_GLSL + STAR_SKY_BODY
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = sky_shader
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.18, 0.2, 0.3)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	var we := WorldEnvironment.new()
	we.environment = env
	_sv.add_child(we)

	# แสงอาทิตย์ + แสงเติมจากทางกล้อง (ให้เห็นตัวกระสวย)
	var sun_dir := SUN_DIR.normalized()
	var sun := DirectionalLight3D.new()
	sun.basis = Basis.looking_at(-sun_dir, Vector3.UP)
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.light_energy = 2.2
	_sv.add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.basis = Basis.looking_at(Vector3(0.2, -0.3, -1.0).normalized(), Vector3.UP)
	fill.light_color = Color(0.55, 0.65, 1.0)
	fill.light_energy = 0.5
	_sv.add_child(fill)

	# ดาวเคราะห์
	var pm := SphereMesh.new()
	pm.radius = PLANET_R
	pm.height = PLANET_R * 2.0
	pm.radial_segments = 128
	pm.rings = 64
	var planet_shader := Shader.new()
	planet_shader.code = "shader_type spatial;\n" + NOISE_GLSL + PLANET_BODY
	var planet_mat := ShaderMaterial.new()
	planet_mat.shader = planet_shader
	planet_mat.set_shader_parameter("sun_dir", sun_dir)
	pm.material = planet_mat
	_planet = MeshInstance3D.new()
	_planet.mesh = pm
	_planet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sv.add_child(_planet)
	_planet.position = PLANET_CENTER

	# ชั้นบรรยากาศหม่นๆ ขอบเรือง
	var am := SphereMesh.new()
	am.radius = PLANET_R * 1.06
	am.height = PLANET_R * 2.12
	am.radial_segments = 96
	am.rings = 48
	var atmo_shader := Shader.new()
	atmo_shader.code = ATMO_SHADER
	var atmo_mat := ShaderMaterial.new()
	atmo_mat.shader = atmo_shader
	atmo_mat.set_shader_parameter("sun_dir", sun_dir)
	am.material = atmo_mat
	var atmo := MeshInstance3D.new()
	atmo.mesh = am
	atmo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sv.add_child(atmo)
	atmo.position = PLANET_CENTER

	# กล้อง
	_space_cam = Camera3D.new()
	_space_cam.fov = 55.0
	_space_cam.near = 0.5
	_space_cam.far = 30000.0
	_sv.add_child(_space_cam)
	_space_cam.make_current()

	# กระสวย (พุ่งเข้าหาจุดที่ใกล้กล้องที่สุดบนดาว จมลงไปในเมฆนิดหน่อย)
	var toward := (-PLANET_CENTER).normalized()
	_space_goal = PLANET_CENTER + toward * (PLANET_R * 0.97)
	_space = _build_shuttle_rig(_sv)
	_build_trails(_space, false)

	# ลูกไฟตอนเข้าบรรยากาศ (บิลบอร์ด เรืองเพิ่มสี)
	var gq := QuadMesh.new()
	gq.size = Vector2(1.0, 1.0)
	_entry_mat = _puff_material()
	_entry_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_entry_mat.billboard_keep_scale = true
	_entry_mat.albedo_color = Color(1.0, 0.62, 0.28, 0.0)
	gq.material = _entry_mat
	_entry_quad = MeshInstance3D.new()
	_entry_quad.mesh = gq
	_entry_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_entry_quad.visible = false
	_space.root.add_child(_entry_quad)
	_entry_quad.position = Vector3(0.0, 2.2, 14.0)

# ===================================================================
# ฉากบนพื้น
# ===================================================================
func _build_ground() -> void:
	_ground = _build_shuttle_rig(get_tree().current_scene)
	_build_trails(_ground, true)
	_set_trails(_ground, false)   # เริ่มปล่อยตอนตัดเข้าฉากนี้ ไม่งั้นกองรวมอยู่ที่จุดเริ่ม
	_build_ground_fx()

func _build_ground_fx() -> void:
	var scene := get_tree().current_scene

	# เมฆฝุ่น: ไล่สีเหมือนกันทั้งระเบิดฝุ่นและฝุ่นลากยาว
	var dg := Gradient.new()
	dg.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	dg.colors = PackedColorArray([
		Color(0.75, 0.6, 0.45, 0.0), Color(0.75, 0.6, 0.45, 0.75), Color(0.6, 0.5, 0.4, 0.0)])
	var dgt := GradientTexture1D.new()
	dgt.gradient = dg

	var dqm := QuadMesh.new()
	dqm.size = Vector2(1.0, 1.0)
	dqm.material = _puff_material()

	# ฝุ่นระเบิดตอนกระแทก (ครั้งเดียว)
	var bpm := ParticleProcessMaterial.new()
	bpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	bpm.emission_box_extents = Vector3(6.0, 0.3, 8.0)
	bpm.direction = Vector3(0.0, 0.15, 0.0)
	bpm.spread = 180.0
	bpm.flatness = 0.85
	bpm.initial_velocity_min = 8.0
	bpm.initial_velocity_max = 22.0
	bpm.damping_min = 3.5
	bpm.damping_max = 5.5
	bpm.gravity = Vector3(0.0, -1.0, 0.0)
	bpm.scale_min = 6.0
	bpm.scale_max = 13.0
	bpm.color_ramp = dgt

	_dust_burst = GPUParticles3D.new()
	_dust_burst.amount = 170
	_dust_burst.lifetime = 4.5
	_dust_burst.one_shot = true
	_dust_burst.explosiveness = 1.0
	_dust_burst.emitting = false
	_dust_burst.local_coords = false
	_dust_burst.visibility_aabb = AABB(Vector3(-90, -10, -90), Vector3(180, 50, 180))
	_dust_burst.process_material = bpm
	_dust_burst.draw_pass_1 = dqm
	_dust_burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(_dust_burst)

	# ฝุ่นลากยาวตามท้องกระสวยตอนไถ (ปล่อยในพิกัดโลก ทิ้งหางไว้ตามทาง)
	var tpm := ParticleProcessMaterial.new()
	tpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	tpm.emission_box_extents = Vector3(4.5, 0.2, 8.0)
	tpm.direction = Vector3(0.0, 0.2, 0.0)
	tpm.spread = 180.0
	tpm.flatness = 0.7
	tpm.initial_velocity_min = 3.0
	tpm.initial_velocity_max = 11.0
	tpm.damping_min = 2.0
	tpm.damping_max = 4.0
	tpm.gravity = Vector3(0.0, -0.6, 0.0)
	tpm.scale_min = 3.0
	tpm.scale_max = 8.0
	tpm.color_ramp = dgt

	_dust_trail = GPUParticles3D.new()
	_dust_trail.amount = 320
	_dust_trail.lifetime = 3.8
	_dust_trail.emitting = false
	_dust_trail.local_coords = false
	_dust_trail.visibility_aabb = AABB(Vector3(-90, -10, -90), Vector3(180, 50, 180))
	_dust_trail.process_material = tpm
	_dust_trail.draw_pass_1 = dqm
	_dust_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ground.root.add_child(_dust_trail)
	_dust_trail.position = Vector3(0.0, 0.3, 9.0)

	# ประกายไฟตอนเหล็กครูดพื้น
	var sg := Gradient.new()
	sg.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	sg.colors = PackedColorArray([
		Color(1.0, 0.95, 0.7, 1.0), Color(1.0, 0.5, 0.1, 0.8), Color(0.6, 0.1, 0.0, 0.0)])
	var sgt := GradientTexture1D.new()
	sgt.gradient = sg

	var spm := ParticleProcessMaterial.new()
	spm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	spm.emission_sphere_radius = 1.2
	spm.direction = Vector3(0.0, 1.0, -0.6)
	spm.spread = 35.0
	spm.initial_velocity_min = 7.0
	spm.initial_velocity_max = 18.0
	spm.gravity = Vector3(0.0, -14.0, 0.0)
	spm.scale_min = 0.5
	spm.scale_max = 1.1
	spm.color_ramp = sgt

	var sqm := QuadMesh.new()
	sqm.size = Vector2(0.14, 0.14)
	var smat := _puff_material()
	smat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sqm.material = smat

	_sparks = GPUParticles3D.new()
	_sparks.amount = 180
	_sparks.lifetime = 0.9
	_sparks.emitting = false
	_sparks.local_coords = false
	_sparks.visibility_aabb = AABB(Vector3(-60, -10, -60), Vector3(120, 40, 120))
	_sparks.process_material = spm
	_sparks.draw_pass_1 = sqm
	_sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ground.root.add_child(_sparks)
	_sparks.position = Vector3(0.0, 0.3, 3.0)

	# ควันดำจากห้องเครื่องที่พังแล้ว (ค้างอยู่หลังคัทซีนจบ)
	var kg := Gradient.new()
	kg.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	kg.colors = PackedColorArray([
		Color(0.12, 0.11, 0.11, 0.0), Color(0.15, 0.14, 0.14, 0.65), Color(0.3, 0.28, 0.27, 0.0)])
	var kgt := GradientTexture1D.new()
	kgt.gradient = kg

	var cv := Curve.new()
	cv.max_value = 2.0
	cv.add_point(Vector2(0.0, 0.4))
	cv.add_point(Vector2(1.0, 1.8))
	var cvt := CurveTexture.new()
	cvt.curve = cv

	var kpm := ParticleProcessMaterial.new()
	kpm.direction = Vector3(0.0, 1.0, 0.0)
	kpm.spread = 12.0
	kpm.initial_velocity_min = 1.5
	kpm.initial_velocity_max = 3.5
	kpm.gravity = Vector3(0.35, 0.5, 0.0)
	kpm.scale_min = 1.2
	kpm.scale_max = 2.4
	kpm.scale_curve = cvt
	kpm.color_ramp = kgt

	var kqm := QuadMesh.new()
	kqm.size = Vector2(1.6, 1.6)
	kqm.material = _puff_material()

	for side in [-1.0, 1.0]:
		var ps := GPUParticles3D.new()
		ps.amount = 70
		ps.lifetime = 5.0
		ps.emitting = false
		ps.local_coords = false
		ps.visibility_aabb = AABB(Vector3(-40, -5, -40), Vector3(80, 70, 80))
		ps.process_material = kpm
		ps.draw_pass_1 = kqm
		ps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ground.root.add_child(ps)
		ps.position = Vector3(side * 5.0, 1.8, 2.8)
		_smoke.append(ps)

# หางไอพ่นของนาเซลล์ทั้งสอง (ฉากอวกาศ = ไอพ่นสะอาดสีฟ้าขาว, ฉากบนพื้น = ไฟปนควันดำ)
# ปล่อยในพิกัดโลก (local_coords = false) จึงลากยาวตามเส้นทางที่กระสวยบินผ่าน
func _build_trails(rig: ShuttleRig, smoky: bool) -> void:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 0.55, 1.0])
	if smoky:
		g.colors = PackedColorArray([
			Color(1.0, 0.85, 0.5, 0.95), Color(1.0, 0.45, 0.12, 0.7),
			Color(0.22, 0.2, 0.2, 0.55), Color(0.18, 0.16, 0.16, 0.0)])
	else:
		g.colors = PackedColorArray([
			Color(0.85, 0.95, 1.0, 0.95), Color(0.45, 0.7, 1.0, 0.65),
			Color(0.3, 0.4, 0.8, 0.3), Color(0.2, 0.25, 0.5, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g

	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.0, 0.0, -1.0)
	pm.spread = 5.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 6.0
	pm.gravity = Vector3(0.0, 0.4, 0.0) if smoky else Vector3.ZERO
	pm.scale_min = 0.8
	pm.scale_max = 1.8
	pm.color_ramp = gt

	var qm := QuadMesh.new()
	qm.size = Vector2(2.2, 2.2) if smoky else Vector2(5.0, 5.0)
	var mat := _puff_material()
	if not smoky:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	qm.material = mat

	for side in [-1.0, 1.0]:
		var ps := GPUParticles3D.new()
		ps.amount = 260
		ps.lifetime = 3.5 if smoky else 4.5
		ps.local_coords = false
		ps.visibility_aabb = AABB(Vector3(-300, -300, -700), Vector3(600, 600, 1400))
		ps.process_material = pm
		ps.draw_pass_1 = qm
		ps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ps.position = Vector3(side * 5.0, 1.4, 1.5)
		rig.root.add_child(ps)
		rig.trails.append(ps)

func _puff_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	return tex

func _puff_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _puff_texture()
	return mat

# ===================================================================
# โมเดลกระสวย (ท้ายอยู่ที่ z=0 ประตูท้ายหันไปทาง -Z หัวชี้ไปทาง +Z)
# ===================================================================
func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	return AlienBuilder.node(bm, mat, parent, pos, rot_deg)

func _cyl(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 16
	return AlienBuilder.node(cm, mat, parent, pos, rot_deg)

# เปลวไอพ่น: ฐานอยู่ที่หัวฉีด ปลายชี้ไปตามทิศไอเสีย (rot_x_deg: -90 = ชี้ -Z, 180 = ชี้ลง)
func _flame(parent: Node3D, pos: Vector3, rot_x_deg: float, radius: float, length: float,
		mat: Material, core_mat: Material) -> Node3D:
	var pv := AlienBuilder.pivot(parent, pos)
	pv.rotation_degrees = Vector3(rot_x_deg, 0.0, 0.0)
	for k in 2:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = radius * (1.0 if k == 0 else 0.5)
		cm.height = length * (1.0 if k == 0 else 0.7)
		cm.radial_segments = 10
		cm.rings = 1
		var mi := AlienBuilder.node(cm, mat if k == 0 else core_mat, pv, Vector3(0.0, cm.height * 0.5, 0.0))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return pv

func _build_shuttle_rig(parent: Node) -> ShuttleRig:
	var rig := ShuttleRig.new()
	rig.root = Node3D.new()
	rig.root.name = "Shuttle"
	parent.add_child(rig.root)
	var shuttle := rig.root

	var hull := AlienBuilder.shell_material(Color(0.16, 0.18, 0.23), 0.5, 0.4)
	var plate := AlienBuilder.shell_material(Color(0.24, 0.2, 0.27), 0.5, 0.4)
	var glow := AlienBuilder.glow_material(SHUTTLE_GLOW, 2.5)
	var warm := AlienBuilder.glow_material(Color(1.0, 0.75, 0.45), 3.0)

	# วัสดุห้องภายใน: ไม่ตัดหน้าหลัง เพื่อให้มองเห็นผนังจากข้างใน
	var inner := StandardMaterial3D.new()
	inner.albedo_color = Color(0.1, 0.11, 0.13)
	inner.metallic = 0.5
	inner.roughness = 0.6
	inner.cull_mode = BaseMaterial3D.CULL_DISABLED

	var flame_mat := StandardMaterial3D.new()
	flame_mat.albedo_color = Color(1.0, 0.5, 0.12, 0.75)
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var core_mat := flame_mat.duplicate() as StandardMaterial3D
	core_mat.albedo_color = Color(1.0, 0.92, 0.75, 0.9)

	# ---------------- ห้องโดยสาร (z 0..8.6) ----------------
	_box(shuttle, Vector3(4.8, 0.06, 8.6), Vector3(0.0, 0.03, 4.3), inner)                 # พื้น
	_box(shuttle, Vector3(4.8, 0.2, 8.6), Vector3(0.0, 3.8, 4.3), inner)                   # เพดาน
	for side in [-1.0, 1.0]:
		_box(shuttle, Vector3(0.3, 3.8, 8.6), Vector3(side * 2.5, 1.9, 4.3), inner)        # ผนัง
		_box(shuttle, Vector3(0.1, 3.9, 8.6), Vector3(side * 2.72, 1.95, 4.3), hull)       # เปลือกนอก
		_box(shuttle, Vector3(0.3, 3.9, 0.3), Vector3(side * 2.5, 1.95, 0.0), plate)       # เสากรอบประตูท้าย
		_box(shuttle, Vector3(0.14, 0.05, 7.4), Vector3(side * 1.3, 3.68, 4.0), warm)      # แถบไฟเพดาน
		_box(shuttle, Vector3(0.08, 0.02, 7.4), Vector3(side * 2.0, 0.07, 4.0), glow)      # แถบไฟพื้น
		for z in [1.2, 3.0, 4.8, 6.6]:
			_box(shuttle, Vector3(0.16, 3.4, 0.22), Vector3(side * 2.32, 1.8, z), plate)   # ซี่โครงผนัง
	_box(shuttle, Vector3(5.3, 3.9, 0.4), Vector3(0.0, 1.95, 8.7), inner)                  # ผนังหน้าห้อง
	_box(shuttle, Vector3(3.0, 1.2, 0.06), Vector3(0.0, 1.7, 8.46), glow)                  # แผงควบคุมเรืองแสง
	_box(shuttle, Vector3(3.4, 0.5, 0.3), Vector3(0.0, 0.45, 8.35), plate)                 # ตู้ด้านล่าง
	_box(shuttle, Vector3(5.4, 0.12, 8.8), Vector3(0.0, 3.97, 4.4), hull)                  # เปลือกหลังคา
	_box(shuttle, Vector3(5.3, 0.35, 0.3), Vector3(0.0, 3.85, 0.0), plate)                 # คานเหนือประตูท้าย
	for z in [1.2, 3.0, 4.8, 6.6]:
		_box(shuttle, Vector3(4.6, 0.18, 0.22), Vector3(0.0, 3.62, z), plate)              # ซี่โครงเพดาน

	rig.bay_light = OmniLight3D.new()
	rig.bay_light.position = Vector3(0.0, 3.0, 4.2)
	rig.bay_light.light_color = Color(1.0, 0.8, 0.55)
	rig.bay_light.light_energy = 1.6
	rig.bay_light.omni_range = 10.0
	shuttle.add_child(rig.bay_light)

	# ---------------- ประตูท้าย (บานพับที่พื้น พับลงเป็นทางลาด) ----------------
	rig.door = AlienBuilder.pivot(shuttle, Vector3(0.0, 0.08, 0.05))
	_box(rig.door, Vector3(4.7, 3.7, 0.14), Vector3(0.0, 1.85, 0.0), inner)
	for y in [0.5, 1.2, 1.9, 2.6, 3.3]:
		_box(rig.door, Vector3(3.6, 0.12, 0.02), Vector3(0.0, y, 0.08), glow)              # แถบเรืองด้านใน (กลายเป็นด้านบนของทางลาด)

	# ---------------- ตัวถังด้านหน้า ----------------
	AlienBuilder.ellipsoid(shuttle, Vector3(0.0, 2.2, 13.0), Vector3(2.9, 2.0, 7.2), hull)
	AlienBuilder.ellipsoid(shuttle, Vector3(0.0, 4.1, 12.0), Vector3(0.5, 0.35, 6.0), plate)   # สันหลัง
	AlienBuilder.ellipsoid(shuttle, Vector3(0.0, 3.2, 17.5), Vector3(1.0, 0.5, 1.8), glow)     # กระจกห้องนักบิน
	AlienBuilder.cone(shuttle, Vector3(0.0, 2.2, 19.5), Vector3(0.0, -0.05, 1.0), 0.9, 3.5, plate)  # ปลายจมูก

	# ปีก + ครีบ + ห้องเครื่อง
	for side in [-1.0, 1.0]:
		AlienBuilder.ellipsoid(shuttle, Vector3(side * 5.0, 1.4, 9.0), Vector3(2.6, 0.3, 4.6), hull,
			Vector3(0.0, 0.0, side * -8.0))
		_box(shuttle, Vector3(0.2, 2.2, 2.2), Vector3(side * 7.2, 2.2, 7.5), plate, Vector3(0.0, 0.0, side * 10.0))
		_cyl(shuttle, 0.75, 4.5, Vector3(side * 5.0, 1.4, 4.6), hull, Vector3(90.0, 0.0, 0.0))      # ห้องเครื่อง
		_cyl(shuttle, 0.8, 0.5, Vector3(side * 5.0, 1.4, 2.3), plate, Vector3(90.0, 0.0, 0.0))      # หัวฉีดท้าย
		_cyl(shuttle, 0.82, 0.5, Vector3(side * 2.0, 0.8, 12.0), plate)                            # หัวฉีดใต้ท้อง

		rig.flames_rear.append(_flame(shuttle, Vector3(side * 5.0, 1.4, 2.0), -90.0, 0.7, REAR_LEN, flame_mat, core_mat))
		rig.flames_belly.append(_flame(shuttle, Vector3(side * 2.0, 0.55, 12.0), 180.0, 0.8, BELLY_LEN, flame_mat, core_mat))

	# เปลวความร้อนรอบหัวตอนเข้าบรรยากาศ
	rig.heat_mat = StandardMaterial3D.new()
	rig.heat_mat.albedo_color = Color(1.0, 0.5, 0.2, 0.4)
	rig.heat_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rig.heat_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rig.heat_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	rig.heat = AlienBuilder.ellipsoid(shuttle, Vector3(0.0, 2.2, 13.0), Vector3(3.5, 2.7, 8.5), rig.heat_mat)
	rig.heat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rig.heat.visible = false

	rig.glow_light = OmniLight3D.new()
	rig.glow_light.position = Vector3(0.0, 2.5, 13.0)
	rig.glow_light.light_color = Color(1.0, 0.6, 0.3)
	rig.glow_light.light_energy = 6.0
	rig.glow_light.omni_range = 80.0
	shuttle.add_child(rig.glow_light)

	return rig

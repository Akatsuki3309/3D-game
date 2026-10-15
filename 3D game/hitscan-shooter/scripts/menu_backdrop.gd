extends Control

# ฉากหลังหน้าเมนูหลัก วาดด้วยโค้ดล้วน ไม่ต้องมีรูป
# ธีม Fallen Earth: ท้องฟ้าฝุ่นสีส้ม ดาวเคราะห์มีวงแหวน ซากเมือง 3 ชั้น (ขยับตามเมาส์ให้ดูมีมิติ)
# ถังไฟไกลๆ กะพริบ เถ้า/ฝุ่นลอย เมฆฝุ่นเลื่อน หมอกที่ขอบฟ้า และขอบมืดรอบจอ
# main_menu.gd สร้างตัวนี้ให้เอง

@export var mouse_parallax := 22.0

var _t := 0.0
var _mouse := Vector2.ZERO
var _stars: Array = []
var _layers: Array = []
var _rocks: Array = []
var _dust: Array = []
var _clouds: Array = []
var _fires: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var rng := RandomNumberGenerator.new()
	rng.seed = 20261010

	# ดาว [x, y, ขนาด, เฟส, ความเร็วกะพริบ]
	for i in 130:
		_stars.append([rng.randf(), rng.randf() * 0.62, rng.randf_range(0.6, 1.8), rng.randf() * TAU, rng.randf_range(0.8, 2.5)])

	# ซากตึก 3 ชั้น [สี, พารัลแลกซ์, ฐาน(สัดส่วนจอ), ความกว้างต่ำ/สูง, ความสูงต่ำ/สูง]
	var defs := [
		[Color(0.34, 0.22, 0.26), 0.25, 0.70, 0.025, 0.06, 0.08, 0.22],
		[Color(0.20, 0.13, 0.17), 0.60, 0.76, 0.035, 0.08, 0.10, 0.30],
		[Color(0.10, 0.07, 0.10), 1.10, 0.83, 0.04, 0.10, 0.12, 0.34],
	]
	for d in defs:
		var blds: Array = []
		var x := -0.08
		while x < 1.1:
			var bw: float = rng.randf_range(d[3], d[4])
			if rng.randf() < 0.2:
				x += bw * rng.randf_range(0.3, 1.2)   # ช่องว่างระหว่างตึก
			# [x, กว้าง, สูง, ความเอียงของยอดที่หัก 0..0.4, มีเสาอากาศไหม]
			blds.append([x, bw, rng.randf_range(d[5], d[6]), rng.randf_range(0.0, 0.4), rng.randf() < 0.3])
			x += bw * rng.randf_range(0.6, 1.1)
		_layers.append({"color": d[0], "par": d[1], "base": d[2], "blds": blds})

	# หินแหลมด้านหน้าสุด [x, กว้าง, สูง]
	var rx := -0.05
	while rx < 1.05:
		var rw := rng.randf_range(0.04, 0.12)
		_rocks.append([rx, rw, rng.randf_range(0.03, 0.11)])
		rx += rw * rng.randf_range(0.5, 0.95)

	# ถังไฟไกลๆ [x, ชั้นที่ตั้ง, เฟส]
	_fires = [[0.2, 1, 0.0], [0.47, 0, 1.7], [0.86, 1, 3.1]]

	# ฝุ่น/เถ้า [x, y, ความเร็วแนวนอน, ความเร็วลอยขึ้น, ขนาด, เฟส]
	for i in 90:
		_dust.append([rng.randf(), rng.randf(), rng.randf_range(0.01, 0.045), rng.randf_range(0.005, 0.03),
			rng.randf_range(1.0, 3.0), rng.randf() * TAU])

	# เมฆฝุ่น [x, y, กว้าง, ความเร็ว, ความทึบ]
	for i in 5:
		_clouds.append([rng.randf(), rng.randf_range(0.06, 0.42), rng.randf_range(0.3, 0.6),
			rng.randf_range(0.004, 0.012), rng.randf_range(0.05, 0.11)])

func _process(delta: float) -> void:
	_t += delta
	var sz := get_viewport_rect().size
	if sz.x > 0.0 and sz.y > 0.0:
		var m := get_viewport().get_mouse_position() / sz - Vector2(0.5, 0.5)
		_mouse = _mouse.lerp(m.clamp(Vector2(-0.5, -0.5), Vector2(0.5, 0.5)), 1.0 - exp(-3.0 * delta))
	queue_redraw()

# ---------------------------------------------------------------
# วาด
# ---------------------------------------------------------------
func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return

	_draw_sky(w, h)
	_draw_stars(w, h)
	_draw_planet(w, h)
	_draw_clouds(w, h)

	_draw_layer(0, w, h)
	_draw_fires(0, w, h)
	_draw_haze(w, h)
	_draw_layer(1, w, h)
	_draw_fires(1, w, h)
	_draw_layer(2, w, h)

	_draw_rocks(w, h)
	_draw_dust(w, h)
	_draw_vignette(w, h)

func _grad(y0: float, y1: float, c0: Color, c1: Color, w: float) -> void:
	draw_polygon(
		PackedVector2Array([Vector2(0, y0), Vector2(w, y0), Vector2(w, y1), Vector2(0, y1)]),
		PackedColorArray([c0, c0, c1, c1]))

func _draw_sky(w: float, h: float) -> void:
	var top := Color(0.04, 0.05, 0.09)
	var mid := Color(0.16, 0.11, 0.17)
	var hor := Color(0.62, 0.34, 0.22)
	var low := Color(0.12, 0.07, 0.07)
	_grad(0.0, h * 0.45, top, mid, w)
	_grad(h * 0.45, h * 0.72, mid, hor, w)
	_grad(h * 0.72, h, hor, low, w)

func _draw_stars(w: float, h: float) -> void:
	for s in _stars:
		var a := 0.35 + 0.65 * (0.5 + 0.5 * sin(_t * s[4] + s[3]))
		var fade := 1.0 - clampf(s[1] / 0.62, 0.0, 1.0) * 0.8   # ใกล้ขอบฟ้าจางลง
		draw_circle(Vector2(s[0] * w + _mouse.x * -4.0, s[1] * h), s[2], Color(1.0, 0.92, 0.85, a * fade))

func _draw_planet(w: float, h: float) -> void:
	var c := Vector2(w * 0.74 + _mouse.x * -10.0, h * 0.26 + _mouse.y * -6.0)
	var r := h * 0.13

	# แสงรอบดาว
	for i in 6:
		draw_circle(c, r * (1.3 + i * 0.25), Color(0.9, 0.5, 0.4, 0.035))

	# วงแหวน (ครึ่งหลังอยู่หลังดาว)
	draw_set_transform(c, -0.35, Vector2(1.0, 0.22))
	draw_arc(Vector2.ZERO, r * 1.75, PI, TAU, 64, Color(0.85, 0.65, 0.55, 0.5), r * 0.12)
	draw_arc(Vector2.ZERO, r * 2.05, PI, TAU, 64, Color(0.8, 0.55, 0.5, 0.25), r * 0.05)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# ตัวดาว + เงาไล่ด้านขวาล่าง
	draw_circle(c, r, Color(0.62, 0.34, 0.33))
	draw_circle(c + Vector2(r * 0.12, r * 0.08), r * 0.8, Color(0.42, 0.22, 0.27, 0.55))
	draw_circle(c + Vector2(r * 0.28, r * 0.18), r * 0.62, Color(0.2, 0.1, 0.18, 0.6))

	# วงแหวนครึ่งหน้า (อยู่หน้าดาว)
	draw_set_transform(c, -0.35, Vector2(1.0, 0.22))
	draw_arc(Vector2.ZERO, r * 1.75, 0.0, PI, 64, Color(0.9, 0.7, 0.6, 0.7), r * 0.12)
	draw_arc(Vector2.ZERO, r * 2.05, 0.0, PI, 64, Color(0.8, 0.55, 0.5, 0.35), r * 0.05)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# ดวงจันทร์เล็ก
	var m := Vector2(w * 0.5 + _mouse.x * -8.0, h * 0.15 + _mouse.y * -5.0)
	draw_circle(m, h * 0.03, Color(0.75, 0.7, 0.72, 0.9))
	draw_circle(m + Vector2(h * 0.008, h * 0.005), h * 0.024, Color(0.4, 0.36, 0.42, 0.5))

func _draw_clouds(w: float, h: float) -> void:
	for c in _clouds:
		var cw: float = c[2] * w
		var cx := fposmod(c[0] * w + _t * c[3] * w + cw * 0.5, w + cw * 2.0) - cw
		draw_set_transform(Vector2(cx + _mouse.x * -14.0, c[1] * h), 0.0, Vector2(1.0, 0.16))
		draw_circle(Vector2.ZERO, cw * 0.5, Color(0.95, 0.55, 0.45, c[4]))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_layer(idx: int, w: float, h: float) -> void:
	var l: Dictionary = _layers[idx]
	var col: Color = l.color
	var off: float = -_mouse.x * mouse_parallax * l.par
	var base: float = h * l.base + _mouse.y * -6.0 * l.par

	for b in l.blds:
		var x: float = b[0] * w + off
		var bw: float = b[1] * w
		var bh: float = b[2] * h
		var slope: float = b[3]
		draw_colored_polygon(PackedVector2Array([
			Vector2(x, base + 2.0),
			Vector2(x, base - bh),
			Vector2(x + bw * 0.55, base - bh * (1.0 - slope * 0.5)),
			Vector2(x + bw, base - bh * (1.0 - slope)),
			Vector2(x + bw, base + 2.0),
		]), col)
		if b[4]:   # เสาอากาศ
			draw_line(Vector2(x + bw * 0.3, base - bh * 0.98), Vector2(x + bw * 0.3, base - bh - h * 0.05), col, 2.0)

	# พื้นใต้ตึกเชื่อมถึงขอบล่างของจอ
	draw_rect(Rect2(0.0, base, w, h - base + 2.0), col)

func _draw_fires(layer_idx: int, w: float, h: float) -> void:
	var l: Dictionary = _layers[layer_idx]
	var off: float = -_mouse.x * mouse_parallax * l.par
	var base: float = h * l.base + _mouse.y * -6.0 * l.par
	for f in _fires:
		if f[1] != layer_idx:
			continue
		var p := Vector2(f[0] * w + off, base - h * 0.008)
		var flick := 0.75 + 0.25 * sin(_t * 9.0 + f[2]) * sin(_t * 5.3 + f[2] * 2.0)
		for i in 5:
			draw_circle(p, h * (0.012 + i * 0.012) * flick, Color(1.0, 0.5, 0.15, 0.1 + 0.05 * (4 - i)))
		draw_circle(p, h * 0.004, Color(1.0, 0.85, 0.5, 0.95))

func _draw_haze(w: float, h: float) -> void:
	# หมอกส้มที่ขอบฟ้า (วาดคั่นระหว่างชั้นตึก ทำให้ชั้นไกลดูจาง)
	var y := h * 0.76
	var clear := Color(0.8, 0.45, 0.3, 0.0)
	var fog := Color(0.8, 0.45, 0.3, 0.22)
	_grad(y - h * 0.12, y, clear, fog, w)
	_grad(y, y + h * 0.06, fog, clear, w)

func _draw_rocks(w: float, h: float) -> void:
	var col := Color(0.03, 0.025, 0.03)
	var off := -_mouse.x * mouse_parallax * 1.6
	var base := h + 2.0
	for r in _rocks:
		var x: float = r[0] * w + off
		var rw: float = r[1] * w
		var rh: float = r[2] * h
		draw_colored_polygon(PackedVector2Array([
			Vector2(x, base),
			Vector2(x + rw * 0.2, base - rh * 0.6),
			Vector2(x + rw * 0.45, base - rh),
			Vector2(x + rw * 0.7, base - rh * 0.55),
			Vector2(x + rw, base),
		]), col)

func _draw_dust(w: float, h: float) -> void:
	for d in _dust:
		var px := fposmod(d[0] * w + _t * d[2] * w + sin(_t * 0.7 + d[5]) * 18.0, w)
		var py := fposmod(d[1] * h - _t * d[3] * h, h)
		var a := 0.15 + 0.5 * (0.5 + 0.5 * sin(_t * 2.0 + d[5]))
		draw_circle(Vector2(px, py), d[4], Color(1.0, 0.62, 0.3, a))

func _draw_vignette(w: float, h: float) -> void:
	var v := Color(0, 0, 0, 0.6)
	var z := Color(0, 0, 0, 0)
	# ซ้ายมืดกว่าให้ตัวอักษรเมนูอ่านง่าย
	var left := Color(0, 0, 0, 0.55)
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w * 0.55, 0), Vector2(w * 0.55, h), Vector2(0, h)]),
		PackedColorArray([left, z, z, left]))
	draw_polygon(PackedVector2Array([Vector2(w * 0.78, 0), Vector2(w, 0), Vector2(w, h), Vector2(w * 0.78, h)]),
		PackedColorArray([z, v, v, z]))
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h * 0.2), Vector2(0, h * 0.2)]),
		PackedColorArray([v, v, z, z]))
	draw_polygon(PackedVector2Array([Vector2(0, h * 0.85), Vector2(w, h * 0.85), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([z, z, v, v]))

extends Control

@export var color := Color(1, 1, 1, 0.9)
@export var outline_color := Color(0, 0, 0, 0.6)
@export var gap := 5.0          # ช่องว่างตรงกลาง
@export var length := 9.0       # ความยาวแต่ละขีด
@export var thickness := 2.0
@export var show_dot := true

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var c := size / 2.0
	var dirs := [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]

	# ขอบดำ (วาดก่อน) ช่วยให้เห็นชัดบนพื้นหลังสว่าง
	for d in dirs:
		draw_line(c + d * (gap - 1.0), c + d * (gap + length + 1.0), outline_color, thickness + 2.0)

	# ขีดสีขาว
	for d in dirs:
		draw_line(c + d * gap, c + d * (gap + length), color, thickness)

	if show_dot:
		draw_circle(c, 1.5, color)

extends StaticBody3D

var hp := 100.0

func take_damage(amount: float) -> void:
	hp -= amount
	print("%s โดนยิง! HP เหลือ %.0f" % [name, hp])
	if hp <= 0:
		queue_free()

extends SceneTree
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _initialize() -> void:
	var w := PWorld.new()
	w.gravity = Vector2(0.0, 900.0)
	w.terminal_speed = 0.0
	w.ccd_enabled = false
	w.sleeping_enabled = false
	var b := PBody.new()
	b.position = Vector2(0.0, 0.0)
	w.add_body(b, [_block(14, 14)])
	print("步     y         vy        awake   accum_force.y   rects")
	for i in 90:
		w.step(1.0 / 60.0)
		if i % 10 == 9:
			print("%3d  %8.2f  %8.2f  %-6s  %12.1f   %d" % [
				i, b.position.y, b.linear_velocity.y, str(b.awake),
				b.accum_force.y, b.rects.size()])
	quit(0)

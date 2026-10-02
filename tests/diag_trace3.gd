extends SceneTree
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

func _initialize() -> void:
	var w := PWorld.new()
	w.use_solver_batch = true
	w.use_threads = false
	w.sleeping_enabled = false
	var g := PBody.new()
	g.position = Vector2(-200.0, 0.0)
	g.make_static()
	w.add_body(g, [_block(400, 40)])
	var b := PBody.new()
	b.position = Vector2(0.0, -20.0)
	w.add_body(b, [_block(14, 14)])
	for i in 12:
		w._batch.debug = (i >= 7)
		if i >= 7:
			print("== step %d ==" % (i + 1))
		w.step(1.0 / 60.0)
		if i >= 7:
			print("  盒子 y=%.4f vy=%.4f" % [b.position.y, b.linear_velocity.y])
	quit(0)

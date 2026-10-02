extends SceneTree
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _shape(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

func _run(label: String, iters: int, friction: float, warm: bool, steps: int) -> void:
	var world := PWorld.new()
	world.solver.iterations = iters
	world.solver.global_friction = friction
	var g := PBody.new()
	g.position = Vector2(0, 200)
	g.make_static()
	world.add_body(g, [_shape(240, 16)])
	var boxes: Array = []
	for i in 3:
		var b := PBody.new()
		b.position = Vector2(100, 184.0 - 16.0 * i)
		world.add_body(b, [_shape(16, 16)])
		boxes.append(b)
	for step in range(steps):
		world.step(1.0 / 60.0)
		if not warm:
			world.solver.clear_warm()
	var top: PBody = boxes[2]
	print("%-28s iters=%-3d mu=%.2f warm=%-5s -> top.x=%8.3f top.rot=%9.6f  b0x=%8.3f" % [
		label, iters, friction, str(warm), top.position.x, top.rotation, boxes[0].position.x])

func _initialize() -> void:
	print("=== stack drift sweep (300 steps, start x=100) ===")
	_run("baseline", 10, 0.5, true, 300)
	_run("no warm start", 10, 0.5, false, 300)
	_run("friction 0", 10, 0.0, true, 300)
	_run("no warm + friction 0", 10, 0.0, false, 300)
	_run("60 iterations", 60, 0.5, true, 300)
	_run("60 iters + no warm", 60, 0.5, false, 300)
	quit(0)

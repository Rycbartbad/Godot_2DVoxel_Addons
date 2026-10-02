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
	var world := PWorld.new()
	world.gravity = Vector2.ZERO
	var wall := PBody.new()
	wall.position = Vector2(200, 0)
	wall.make_static()
	world.add_body(wall, [_block(1, 300)])
	var b := PBody.new()
	b.position = Vector2(60, 140)
	world.add_body(b, [_block(12, 12)])
	b.linear_velocity = Vector2(5000, 0)
	print("step |   x     |   v.x    | substeps | manifolds | sep")
	for i in 12:
		world.step(1.0 / 60.0)
		var s := ""
		if world.manifolds.size() > 0:
			s = "%.3f" % world.manifolds[0].points[0].separation
		print("%4d | %7.2f | %8.1f | %8d | %9d | %s" % [
			i, b.position.x, b.linear_velocity.x, world.last_substeps, world.manifolds.size(), s])
	quit(0)

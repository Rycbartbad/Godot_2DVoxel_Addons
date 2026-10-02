extends SceneTree
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _block(w: int, h: int, mat: int = 1) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, mat)
	return s

func _initialize() -> void:
	var world := PWorld.new()
	world.gravity = Vector2.ZERO
	var wall := PBody.new()
	wall.position = Vector2(200, 0)
	wall.make_static()
	world.add_body(wall, [_block(8, 200)])
	var b := PBody.new()
	b.position = Vector2(50, 100)
	b.ccd = true
	world.add_body(b, [_block(12, 12)])
	b.linear_velocity = Vector2(3000, 0)
	print("墙 200..208，箱宽 12。x 每 2 帧打一次（墙距离 = 200-(x+12)）")
	for i in 40:
		var pen0 := (b.position.x + 12.0) - 200.0
		world.step(1.0 / 60.0)
		if i % 2 == 0 or pen0 > -10.0:
			print("  帧%2d x=%9.3f vx=%10.2f 子步=%2d 挤入时pen=%7.3f 伪vx=%8.3f" % [
				i, b.position.x, b.linear_velocity.x, world.last_substeps, pen0,
				b.pseudo_linear_velocity.x])
	quit(0)

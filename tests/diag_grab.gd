extends SceneTree
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const Grab := preload("res://src/physics/grab.gd")

func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

func _initialize() -> void:
	var world := PWorld.new()
	world.gravity = Vector2.ZERO
	var b := PBody.new()
	b.position = Vector2(100, 100)
	world.add_body(b, [_block(20, 20)])
	var g: Grab = world.grab(b, b.com_world(), 2500.0)
	world.set_grab_target(Vector2(250, 100))
	print("mass=", b.mass, " inv_mass=", b.inv_mass, " 目标 x=250, 起点 com=110")
	print("step |  com.x  |   v.x    | substeps | 饱和 | 每步位移 | 本步最大冲量上限")
	for i in 24:
		var x0 := b.com_world().x
		world.step(1.0 / 60.0)
		print("%4d | %7.2f | %8.1f | %8d | %4s | %8.3f | %.1f" % [
			i, b.com_world().x, b.linear_velocity.x, world.last_substeps,
			str(world._ccd_saturated), b.com_world().x - x0,
			2500.0 * b.mass * (1.0 / 60.0)])
	quit(0)

extends SceneTree
## 探针：铰链速度马达的稳态角速度 vs damping（Rapier AccelerationBased 马达）
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _shape(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

func _run(damp: float, target: float, max_force: float) -> float:
	var world := PWorld.new()
	world.gravity = Vector2.ZERO
	world.rp_angular_damping = 0.0
	var b := PBody.new()
	b.position = Vector2(100, 100)
	world.add_body(b, [_shape(16, 16)])
	var j = world.add_hinge(b, null, Vector2(100, 100))
	j.set_motor_velocity(target, max_force, damp)
	for i in 180:
		world.step(1.0 / 60.0)
	return j.speed()

func _initialize() -> void:
	for d in [1.0, 10.0, 100.0, 1000.0, 10000.0]:
		print("damping %8.1f -> speed %.4f" % [d, _run(d, 3.0, 1.0e9)])
	print("target 0.5, damping 100 -> %.4f" % _run(100.0, 0.5, 1.0e9))
	print("target 3, damping 100, max_force 1e3 -> %.4f" % _run(100.0, 3.0, 1.0e3))
	print("target 3, damping 100, max_force 1e5 -> %.4f" % _run(100.0, 3.0, 1.0e5))
	quit(0)

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

func _trial(dist: float, label: String) -> void:
	var world := PWorld.new()
	world.gravity = Vector2.ZERO
	var b := PBody.new()
	b.position = Vector2(100, 100)
	world.add_body(b, [_block(20, 20)])
	var g: Grab = world.grab(b, b.com_world())
	world.set_grab_target(Vector2(100 + dist + 10.0, 110))
	var peak := 0.0
	var past := 0.0
	for i in 120:
		world.step(1.0 / 60.0)
		peak = maxf(peak, b.linear_velocity.length())
		past = maxf(past, b.com_world().x - (100 + dist + 10.0))
	print("  目标挪 %5.0f 单位: 峰值速度 %6.1f | 最大超调 %6.3f | 2 秒后误差 %6.3f" % [
		dist, peak, past, absf(b.com_world().x - (100 + dist + 10.0))])

func _initialize() -> void:
	print("=== 抓取手感（临界阻尼）===")
	for d in [20.0, 60.0, 150.0, 400.0]:
		_trial(d, "")
	quit(0)

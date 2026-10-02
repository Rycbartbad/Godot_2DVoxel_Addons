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
	# 先正常跑，直到接近墙
	var frame := 0
	while b.position.x < 160.0 and frame < 50:
		world.step(1.0 / 60.0)
		frame += 1
	print("第 %d 帧末 x=%.4f vx=%.2f —— 下面手工逐子步" % [frame, b.position.x, b.linear_velocity.x])
	var n := world._compute_substeps(1.0 / 60.0)
	var sub := 1.0 / 60.0 / float(n)
	print("本轮子步数 = %d（子步 dt = %.6f，每个子步位移 = %.4f）" % [n, sub, 3000.0 * sub])
	for i in n:
		var x0 := b.position.x
		world._substep(sub)
		print("  子步%2d x %8.4f -> %8.4f (移动 %7.4f, 墙面距离 %8.4f) vx=%9.2f" % [
			i, x0, b.position.x, b.position.x - x0, 200.0 - (b.position.x + 12.0), b.linear_velocity.x])
		if b.position.x > 200.0:
			break
	quit(0)

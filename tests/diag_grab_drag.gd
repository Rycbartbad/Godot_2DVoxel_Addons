extends SceneTree
## 拖动诊断：抓住一个方块、把目标平移，看 30 帧里到底发生了什么。
## 重点看 accum_force —— 它是**持久累加器**，没人 clear 的话会一帧一帧涨。
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _initialize() -> void:
	print("=== 拖动诊断 ===")
	var w := PWorld.new()
	var g := PBody.new()
	g.position = Vector2(-300.0, 0.0)
	g.make_static()
	w.add_body(g, [_block(600, 40)])
	var b := PBody.new()
	b.position = Vector2(0.0, -16.0)
	w.add_body(b, [_block(16, 16)])
	for i in 30:
		w.step(1.0 / 60.0)
	print("落定后：位置 (%.2f, %.2f)  质量 %.0f" % [b.position.x, b.position.y, b.mass])

	var gb = w.grab(b, b.com_world(), 2500.0)
	var target := b.com_world() + Vector2(150.0, 0.0)
	w.set_grab_target(target)
	print("目标 = (%.1f, %.1f)" % [target.x, target.y])
	print("帧   位置x    速度x     accum_force.x   accum_torque   到目标距离")
	for i in 40:
		w.step(1.0 / 60.0)
		if i < 12 or i % 10 == 9:
			print("%3d  %8.2f  %8.2f   %12.2f   %10.2f   %8.2f" % [
				i, b.position.x, b.linear_velocity.x,
				b.accum_force.x, b.accum_torque,
				b.com_world().distance_to(target)])
	print("")
	print("终态：位置 (%.2f, %.2f)  速度 (%.2f, %.2f)  accum_force=(%.2f, %.2f)" % [
		b.position.x, b.position.y, b.linear_velocity.x, b.linear_velocity.y,
		b.accum_force.x, b.accum_force.y])
	print("目标 x=%.1f，终态 x=%.2f" % [target.x, b.position.x])
	quit(0)

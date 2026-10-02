extends SceneTree
## 逐帧追踪：从第一次接触开始，把**求解器的输入**（separation / 偏置）和
## **输出**（累积冲量）逐帧打出来，判断究竟是"数值轨道不同"还是"真 bug"。
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

func _scene(batch: bool) -> PWorld:
	var w := PWorld.new()
	w.use_solver_batch = batch
	w.use_threads = false
	w.sleeping_enabled = false
	var g := PBody.new()
	g.position = Vector2(-200.0, 0.0)
	g.make_static()
	w.add_body(g, [_block(400, 40)])
	var b := PBody.new()
	b.position = Vector2(0.0, -20.0)
	w.add_body(b, [_block(14, 14)])
	return w

func _trace(label: String, w: PWorld) -> void:
	var b: PBody = w.bodies[1]
	var s := ""
	for m in w.manifolds:
		for p in m.points:
			s += " sep=%9.6f vb=%9.4f ni=%9.4f pni=%9.4f" % [
				p.separation, p.velocity_bias, p.normal_impulse, p.pseudo_normal_impulse]
	print("  %-5s y=%9.5f vy=%9.4f w=%9.6f | 流形%d%s" % [
		label, b.position.y, b.linear_velocity.y, b.angular_velocity, w.manifolds.size(), s])

func _initialize() -> void:
	var wa := _scene(false)
	var wb := _scene(true)
	print("步 | 对象路径 / SoA 路径（接触量）")
	for i in 14:
		wa.step(1.0 / 60.0)
		wb.step(1.0 / 60.0)
		if i >= 6:
			print("--- step %d ---" % (i + 1))
			_trace("对象", wa)
			_trace("SoA ", wb)
	quit(0)

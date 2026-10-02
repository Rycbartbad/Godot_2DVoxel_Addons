extends SceneTree
## SoA 路径的**稳定性**检查：单箱落到地面，跑 300 步。
## 如果只是精度不同，箱子应该照样稳稳落在地面上；
## 如果它穿模 / 一直抖 / 掉下去，那就是真有 bug，跟精度无关。
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

func _scene(use_batch: bool) -> PWorld:
	var w := PWorld.new()
	w.sleeping_enabled = false
	w.use_threads = false
	w.use_solver_batch = use_batch
	var g := PBody.new()
	g.position = Vector2(-200.0, 0.0)
	g.make_static()
	w.add_body(g, [_block(400, 40)])
	var b := PBody.new()
	b.position = Vector2(0.0, -20.0)
	w.add_body(b, [_block(14, 14)])
	return w

func _run(label: String, use_batch: bool) -> void:
	var w := _scene(use_batch)
	for i in 300:
		w.step(1.0 / 60.0)
	var b: PBody = w.bodies[1]
	var deepest := 0.0
	for st in 60:
		w.step(1.0 / 60.0)
		deepest = maxf(deepest, b.aabb.end.y)
	print("%-10s 300 步后: y=%9.4f 底边 y=%9.4f 速度=(%.4f, %.4f) 旋转=%.6f | 之后 60 步最深嵌入 %.4f" % [
		label, b.position.y, b.aabb.end.y, b.linear_velocity.x, b.linear_velocity.y,
		b.rotation, deepest])

func _initialize() -> void:
	print("=== 单箱落地稳定性（无休眠）===")
	_run("对象路径", false)
	_run("SoA 路径", true)
	quit(0)

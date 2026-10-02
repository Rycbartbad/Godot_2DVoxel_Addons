extends SceneTree
## 打开 no_warm，看 SoA 路径是否恢复正常
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _shape(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

func _stack(batch: bool, no_warm: bool) -> Array:
	var w := PWorld.new()
	w.use_solver_batch = batch
	w.use_threads = false
	if batch:
		w._batch.no_warm = no_warm
	var g := PBody.new()
	g.position = Vector2(0.0, 200.0)
	g.make_static()
	w.add_body(g, [_shape(240, 16)])
	var boxes: Array = []
	for i in 3:
		var b := PBody.new()
		b.position = Vector2(100.0, 200.0 - 16.0 * float(i + 1))
		w.add_body(b, [_shape(16, 16)])
		boxes.append(b)
	for s in 900:
		w.step(1.0 / 60.0)
	var top: PBody = boxes[2]
	return [top.position.x, top.rotation]

func _drop(batch: bool, no_warm: bool) -> Array:
	var w := PWorld.new()
	w.use_solver_batch = batch
	w.use_threads = false
	w.sleeping_enabled = false
	if batch:
		w._batch.no_warm = no_warm
	var g := PBody.new()
	g.position = Vector2(-200.0, 0.0)
	g.make_static()
	w.add_body(g, [_shape(400, 40)])
	var b := PBody.new()
	b.position = Vector2(0.0, -20.0)
	w.add_body(b, [_shape(14, 14)])
	for i in 300:
		w.step(1.0 / 60.0)
	return [b.position.y, b.rotation, b.aabb.end.y]

func _initialize() -> void:
	print("=== 三层堆叠 900 步：顶层 x / rot ===")
	print("  对象          %.4f / %.6f" % _stack(false, false))
	print("  SoA(warm)     %.4f / %.6f" % _stack(true, false))
	print("  SoA(no warm)  %.4f / %.6f" % _stack(true, true))
	print("=== 单箱落地 300 步：y / rot / 底边 ===")
	print("  对象          %.4f / %.6f / %.4f" % _drop(false, false))
	print("  SoA(warm)     %.4f / %.6f / %.4f" % _drop(true, false))
	print("  SoA(no warm)  %.4f / %.6f / %.4f" % _drop(true, true))
	quit(0)

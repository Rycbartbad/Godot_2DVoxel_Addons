extends SceneTree
## 隔离：是块求解器（2 点流形）的问题，还是通用路径的问题？
## 4 个配置交叉：对象/SoA x 开/关块求解器。三层堆叠 900 步。
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _shape(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

func _run(batch: bool, block: bool) -> void:
	var w := PWorld.new()
	w.use_solver_batch = batch
	w.use_threads = false
	w.solver.use_block_solver = block
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
	var pts: Array = []
	for s in 900:
		w.step(1.0 / 60.0)
		if s < 3 or s % 60 == 0:
			pts.append("%d:%.4f" % [s, (boxes[2] as PBody).position.x])
	var top: PBody = boxes[2]
	print("%-6s %-8s 顶层 x=%9.4f rot=%9.6f | 盒子底边 y=%9.3f/%9.3f/%9.3f | %s" % [
		"SoA" if batch else "对象", "块求解" if block else "标量",
		top.position.x, top.rotation,
		(boxes[0] as PBody).aabb.end.y, (boxes[1] as PBody).aabb.end.y, (boxes[2] as PBody).aabb.end.y,
		" ".join(pts.slice(0, 6))])

func _initialize() -> void:
	print("=== 三层堆叠 900 步：块求解器 x SoA ===")
	_run(false, true)
	_run(false, false)
	_run(true, true)
	_run(true, false)
	quit(0)

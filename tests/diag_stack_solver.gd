extends SceneTree
## 隔离实验：三块叠放的稳定性由什么决定
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _run(name: String, iters: int, gap: float, warm: bool, steps: int = 300) -> void:
	var w := PWorld.new()
	w.solver.iterations = iters
	var g := PBody.new()
	g.position = Vector2(-300.0, 400.0)
	g.make_static()
	w.add_body(g, [_block(600, 40)])
	var boxes: Array = []
	for i in 3:
		var b := PBody.new()
		b.position = Vector2(0.0, 400.0 - 20.0 * (i + 1) - gap * (i + 1))
		w.add_body(b, [_block(20, 20)])
		boxes.append(b)
	var worst := 0.0
	var prev: Array = [0.0, 0.0, 0.0]
	for step in steps:
		if not warm:
			w.solver.clear_warm()
		w.step(1.0 / 60.0)
		if step > steps / 2:
			for i in 3:
				worst = maxf(worst, absf(boxes[i].position.y - prev[i]))
		for i in 3:
			prev[i] = boxes[i].position.y
	var awake := 0
	for b in boxes:
		if b.awake:
			awake += 1
	var pen0: float = (boxes[0].position.y + 20.0) - 400.0
	var pen1: float = (boxes[1].position.y + 20.0) - boxes[0].position.y
	var pen2: float = (boxes[2].position.y + 20.0) - boxes[1].position.y
	var vmax := 0.0
	for b in boxes:
		vmax = maxf(vmax, absf(b.linear_velocity.y))
	print("  %-30s 穿透 %6.3f %6.3f %6.3f | vmax %6.3f | 后段每步位移 %7.5f | 清醒 %d/3" % [
		name, pen0, pen1, pen2, vmax, worst, awake])

func _initialize() -> void:
	print("=== 间隙扫描（iterations=10，warm on）===")
	for gp in [0.0, 0.5, 1.0, 2.0, 4.0, 8.0]:
		_run("gap=%.1f" % gp, 10, gp, true)
	print("=== 迭代扫描（gap=8）===")
	for it in [10, 20, 30, 40, 60]:
		_run("iters=%d gap=8" % it, it, 8.0, true)
	print("=== warm start（gap=8, iters=10）===")
	_run("warm=off", 10, 8.0, false)
	_run("warm=on", 10, 8.0, true)
	print("=== 更高叠层（gap=2, iters=10）===")
	_run("gap=2", 10, 2.0, true)
	quit(0)

extends SceneTree
## 定位：towers 场景里哪一块箱子陷进地面、从哪一步开始
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _initialize() -> void:
	var world := PWorld.new()
	world.sleeping_enabled = false
	world.use_threads = true
	world.use_coloring = false
	var g := PBody.new()
	g.position = Vector2(-600.0, 0.0)
	g.make_static()
	world.add_body(g, [_block(1200, 40)])
	var boxes: Array = []
	for p in 20:
		var gx := -560.0 + float(p) * 40.0
		for i in 4:
			var b := PBody.new()
			b.position = Vector2(gx, -7.0 - float(i) * 16.0)
			world.add_body(b, [_block(14, 14)])
			boxes.append(b)
	var worst := -1e18
	var worst_i := -1
	var first_sink_step := -1
	print("步   最低底边 y   是哪一块   子步 流形")
	for step in 660:
		world.step(1.0 / 60.0)
		var low := -1e18
		var li := -1
		for k in boxes.size():
			var e: float = boxes[k].aabb.end.y
			if e > low:
				low = e
				li = k
		if low > 1.0 and first_sink_step < 0:
			first_sink_step = step
		if low > worst:
			worst = low
			worst_i = li
		if step % 60 == 0 or (low > 1.0 and step % 10 == 0):
			print("%3d  %10.2f   塔%d/层%d   %d   %d" % [step, low, li / 4, li % 4,
				world.last_substeps, world.manifolds.size()])
	print("=== 结论 ===")
	print("  最低底边 %.2f px（地面顶 y=0）" % worst)
	print("  是第 %d 块：塔 %d 第 %d 层" % [worst_i, worst_i / 4, worst_i % 4])
	print("  第一次超过 y=1.0 在第 %d 步" % first_sink_step)
	quit(0)

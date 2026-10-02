extends SceneTree
## 岛任务到底有没有真的并发？直接记录每个岛任务跑在哪个线程、什么时候开始结束。
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

func _towers(n: int) -> PWorld:
	var world := PWorld.new()
	world.sleeping_enabled = false
	world.ccd_enabled = false
	var g := PBody.new()
	g.position = Vector2(-2000.0, 0.0)
	g.make_static()
	world.add_body(g, [_block(4000, 40)])
	for p in n:
		var gx := -1800.0 + float(p) * 40.0
		for i in 3:
			var b := PBody.new()
			b.position = Vector2(gx, -7.0 - float(i) * 14.0)
			world.add_body(b, [_block(14, 14)])
	return world

func _probe(label: String, high: bool, tasks: int) -> void:
	var world := _towers(36)
	world.use_threads = true
	world.use_coloring = false
	world.parallel_high_priority = high
	world.parallel_tasks_needed = tasks
	for i in 60:
		world.step(1.0 / 60.0)
	world.trace_enabled = true
	# 单次 _solve，采集 trace
	var t0 := Time.get_ticks_usec()
	world._solve(1.0 / 60.0)
	var wall := (Time.get_ticks_usec() - t0) / 1000.0
	world.trace_enabled = false
	var tr := world.parallel_trace
	var threads := {}
	var work := 0.0
	var first := 1.0e18
	var last := 0.0
	var manifolds := 0
	var max_m := 0
	var n := 0
	for r: Array in tr:
		if r == null:
			continue
		n += 1
		threads[r[0]] = true
		work += float(r[2] - r[1])
		first = minf(first, float(r[1]))
		last = maxf(last, float(r[2]))
		manifolds += r[3]
		max_m = maxi(max_m, r[3])
	var span := (last - first) / 1000.0
	print("  %-18s high=%-5s tasks=%-3d | 岛任务 %2d 个(共 %3d 流形, 最大岛 %3d) | 线程 %2d | 墙钟 %6.2f ms | 各任务合计 %6.2f ms | 跨度 %6.2f ms | 并行度 %5.2fx" % [
		label, str(high), tasks, n, manifolds, max_m, threads.size(), wall,
		work / 1000.0, span, (work / 1000.0) / maxf(0.001, span)])

func _initialize() -> void:
	print("=== 单次 _solve 的岛任务并发情况（36 塔）===")
	_probe("低优先级 auto", false, -1)
	_probe("高优先级 auto", true, -1)
	_probe("高优先级 t=4", true, 4)
	_probe("高优先级 t=8", true, 8)
	_probe("高优先级 t=16", true, 16)
	quit(0)

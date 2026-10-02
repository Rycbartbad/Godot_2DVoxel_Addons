extends SceneTree
## SoA 求解器 A/B：同一个进程里切换，避免机器漂移。
## 关心两件事：(1) 串行是否更快；(2) 并行度是否真的解开了（原来被 4 线程卡死）。
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

func _build(kind: String) -> PWorld:
	var world := PWorld.new()
	world.sleeping_enabled = false
	world.ccd_enabled = false
	var g := PBody.new()
	g.position = Vector2(-2000.0, 0.0)
	g.make_static()
	world.add_body(g, [_block(4000, 40)])
	var parts := kind.split(":")
	match parts[0]:
		"towers":
			for p in int(parts[1]):
				var gx := -1800.0 + float(p) * 40.0
				for i in 3:
					var bb := PBody.new()
					bb.position = Vector2(gx, -7.0 - float(i) * 14.0)
					world.add_body(bb, [_block(14, 14)])
		"pile":
			for r2 in int(parts[2]):
				for c2 in int(parts[1]):
					var b2 := PBody.new()
					b2.position = Vector2(-200.0 + float(c2) * 14.0 + 7.0, -7.0 - float(r2) * 14.0)
					world.add_body(b2, [_block(14, 14)])
		"frags":
			for i2 in int(parts[1]):
				var f := PBody.new()
				f.position = Vector2(-1200.0 + float(i2 % 60) * 12.0, -400.0 - float(i2 / 60) * 14.0)
				world.add_body(f, [_block(4, 4)])
				f.linear_velocity = Vector2(-120.0 + float(i2 % 13) * 20.0, 100.0)
	return world

func _once(kind: String, batch: bool, threads: bool, steps: int) -> Array:
	var w := _build(kind)
	w.use_solver_batch = batch
	w.use_threads = threads
	for i in 60:
		w.step(1.0 / 60.0)
	var solve := 0
	var broad := 0
	for s in steps:
		var dt := 1.0 / 60.0
		var n: int = w._compute_substeps(dt)
		for i in n:
			var sub: float = dt / float(n)
			var t0 := Time.get_ticks_usec()
			for b0: PBody in w.bodies:
				b0.clear_pseudo()
			w._integrate_forces(sub)
			var t1 := Time.get_ticks_usec()
			w._broadphase(sub)
			var t2 := Time.get_ticks_usec()
			w._wake_pass()
			w._solve(sub)
			var t3 := Time.get_ticks_usec()
			broad += t2 - t1
			solve += t3 - t2
	return [float(solve) / 1000.0 / float(steps), float(broad) / 1000.0 / float(steps),
		w.manifolds.size(), w.last_parallel_tasks]

func _row(kind: String, steps: int, reps: int) -> void:
	var best := {}
	for cfg in [["对象·串行", false, false], ["对象·并行", false, true],
			["SoA·串行", true, false], ["SoA·并行", true, true]]:
		best[cfg[0]] = []
	for r in reps:
		for cfg in [["对象·串行", false, false], ["对象·并行", false, true],
				["SoA·串行", true, false], ["SoA·并行", true, true]]:
			(best[cfg[0]] as Array).append(_once(kind, cfg[1], cfg[2], steps))
	print("\n--- %s ---" % kind)
	var base := 0.0
	for k in ["对象·串行", "对象·并行", "SoA·串行", "SoA·并行"]:
		var arr: Array = best[k]
		var mn := 1.0e18
		var info: Array = arr[0]
		for e: Array in arr:
			if e[0] < mn:
				mn = e[0]
				info = e
		if base == 0.0:
			base = mn
		print("  %-10s solve %7.3f ms | broad %6.3f | solve/broad %5.2f | 加速 %5.2fx | 流形 %d | 岛任务 %d" % [
			k, mn, info[1], mn / maxf(0.001, info[1]), base / maxf(0.001, mn), info[2], info[3]])

func _initialize() -> void:
	print("=== SoA 求解器 A/B（同一进程，reps 取最小值）===")
	_row("towers:36", 30, 5)
	_row("pile:8:6", 30, 5)
	_row("frags:240", 30, 5)
	quit(0)

extends SceneTree
## 隔离**求解阶段**，扫描并行任务参数。
## 上一轮把 high_priority 从 false 改成 true 之后整体反而变慢了（0.60x），
## 这和微基准（3.9x -> 15.0x）矛盾 —— 所以直接测求解阶段本身，并扫描任务数。
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
	if parts[0] == "towers":
		for p in int(parts[1]):
			var gx := -1800.0 + float(p) * 40.0
			for i in 3:
				var b := PBody.new()
				b.position = Vector2(gx, -7.0 - float(i) * 14.0)
				world.add_body(b, [_block(14, 14)])
	elif parts[0] == "pile":
		for r in int(parts[2]):
			for c in int(parts[1]):
				var b2 := PBody.new()
				b2.position = Vector2(-200.0 + float(c) * 14.0 + 7.0, -7.0 - float(r) * 14.0)
				world.add_body(b2, [_block(14, 14)])
	elif parts[0] == "frags":
		for i in int(parts[1]):
			var f := PBody.new()
			f.position = Vector2(-1200.0 + float(i % 60) * 12.0, -400.0 - float(i / 60) * 14.0)
			world.add_body(f, [_block(4, 4)])
			f.linear_velocity = Vector2(-120.0 + float(i % 13) * 20.0, 100.0)
	return world

## 配置：[名称, use_threads, use_coloring, high_priority, tasks_needed]
func _cfg_list() -> Array:
	return [
		["串行",              false, false, true, -1],
		["岛-低优先级",        true,  false, false, -1],
		["岛-高优先级",        true,  false, true,  -1],
		["岛-高 tasks=4",     true,  false, true,   4],
		["岛-高 tasks=8",     true,  false, true,   8],
		["岛-高 tasks=16",    true,  false, true,  16],
		["着色-高优先级",      true,  true,  true,  -1],
		["着色-低优先级",      true,  true,  false, -1],
	]

func _once(kind: String, cfg: Array, steps: int) -> Array:
	var world := _build(kind)
	world.use_threads = cfg[1]
	world.use_coloring = cfg[2]
	world.parallel_high_priority = cfg[3]
	world.parallel_tasks_needed = cfg[4]
	world.solver.color_high_priority = cfg[3]
	world.solver.color_tasks_needed = cfg[4]
	for i in 60:
		world.step(1.0 / 60.0)
	# 只测求解阶段：prepare + _solve，不测积分/窄相
	var t0 := Time.get_ticks_usec()
	for i in steps:
		world.solver.prepare(world.manifolds, 1.0 / 60.0)
		world._solve(1.0 / 60.0)
	var solve_ms := (Time.get_ticks_usec() - t0) / 1000.0 / float(steps)
	# 再测整步
	var t1 := Time.get_ticks_usec()
	for i in steps:
		world.step(1.0 / 60.0)
	var step_ms := (Time.get_ticks_usec() - t1) / 1000.0 / float(steps)
	return [solve_ms, step_ms, world.manifolds.size(), world.last_parallel_tasks]

func _run(kind: String, steps: int, reps: int) -> void:
	var cfgs := _cfg_list()
	var res := {}
	for c in cfgs:
		res[c[0]] = []
	for r in reps:
		for c in cfgs:
			(res[c[0]] as Array).append(_once(kind, c, steps))
	var info: Array = (res["串行"] as Array)[0]
	print("\n--- %s  流形 %d ---" % [kind, info[2]])
	var base: float = (res["串行"] as Array)[0][0]
	for c2 in cfgs:
		var arr: Array = res[c2[0]]
		var mn := 1.0e18
		var mn_step := 1.0e18
		for e: Array in arr:
			mn = minf(mn, e[0])
			mn_step = minf(mn_step, e[1])
		print("  %-16s solve %7.3f ms (%4.2fx) | step %7.3f ms | 任务数 %d" % [
			c2[0], mn, base / maxf(0.001, mn), mn_step, info[3]])

func _initialize() -> void:
	print("=== 求解阶段并行参数扫描（16 核, 交叉重复取最小值）===")
	_run("towers:36", 30, 5)
	_run("frags:240", 30, 5)
	_run("pile:8:6", 30, 5)
	quit(0)

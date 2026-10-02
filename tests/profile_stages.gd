extends SceneTree
## 物理帧耗时分解 —— **带调用次数**，且口径唯一：
##   · 每帧量 = 总计数 / 步数
##   · 每子步量 = 总计数 / 总子步数
## 教训（开发日志坑 17）：只统计累计耗时不够。"每个阶段都不慢"和"整帧很慢"
## 可以同时成立 —— 如果有个乘数（子步数）在放大一切，逐阶段看每一段都正常。
## 与 tests/profile_step.gd 的区别：这里走**真正的** world._solve()
## （含岛并行 / 着色分支），而不是直接调 solver.solve()。
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

## 地面横跨 x∈[-1500,1500]，顶面 y=400。所有物体都放得进去，
## 否则会有物体掉出世界边缘**永远加速**，把子步永久顶满（正是坑 17 的第二个原因）。
func _floor(world: PWorld) -> void:
	var g := PBody.new()
	g.position = Vector2(-1500.0, 400.0)
	g.make_static()
	world.add_body(g, [_block(3000, 40)])

func _scene(kind: String, sleeping: bool) -> PWorld:
	var world := PWorld.new()
	world.sleeping_enabled = sleeping
	_floor(world)
	if kind == "boxes" or kind == "both":
		# 8 宽 x 5 高，面贴面堆叠 => 大量真实接触
		for i in 40:
			var b := PBody.new()
			b.position = Vector2(100.0 + float(i % 8) * 16.0, 393.0 - float(i / 8) * 16.0)
			world.add_body(b, [_block(14, 14)])
	if kind == "frags" or kind == "both":
		for i in 240:
			var f := PBody.new()
			f.position = Vector2(-1200.0 + float(i % 60) * 12.0, 100.0 - float(i / 60) * 14.0)
			world.add_body(f, [_block(4, 4)])
			f.linear_velocity = Vector2(-120.0 + float(i % 13) * 20.0, -60.0 - float(i % 7) * 20.0)
	return world

func _profile(label: String, kind: String, sleeping: bool, steps: int, threads: bool) -> void:
	var world := _scene(kind, sleeping)
	world.use_threads = threads
	world.profile_enabled = true
	for i in 120:
		world.step(1.0 / 60.0)
	var acc := {"pseudo": 0.0, "forces": 0.0, "broad": 0.0, "wake": 0.0,
		"solve": 0.0, "warm": 0.0, "xform": 0.0, "aabb": 0.0, "sleep": 0.0}
	var sub_hist := {}
	var counts := {}
	var dynamic := 0
	var awake := 0
	for b in world.bodies:
		if not b.is_static:
			dynamic += 1
			if b.awake:
				awake += 1
	var t_all := Time.get_ticks_usec()
	for s in steps:
		var dt := 1.0 / 60.0
		var n: int = world._compute_substeps(dt)
		sub_hist[n] = sub_hist.get(n, 0) + 1
		# 必须手动清零：profile_counts 平时是在 step() 开头清的，
		# 而这个剖面循环是手工展开子步的，不会走到那一行。
		# 忘了清 => 计数按帧**累加**，除以步数仍然被放大 30 倍（实测踩过）。
		world.profile_counts = {}
		for i in n:
			var sub: float = dt / float(n)
			var t: int
			t = Time.get_ticks_usec()
			for b0 in world.bodies:
				b0.clear_pseudo()
			acc["pseudo"] += Time.get_ticks_usec() - t
			t = Time.get_ticks_usec(); world._integrate_forces(sub); acc["forces"] += Time.get_ticks_usec() - t
			t = Time.get_ticks_usec(); world._broadphase(sub); acc["broad"] += Time.get_ticks_usec() - t
			t = Time.get_ticks_usec(); world._wake_pass(); acc["wake"] += Time.get_ticks_usec() - t
			t = Time.get_ticks_usec(); world._solve(sub); acc["solve"] += Time.get_ticks_usec() - t
			t = Time.get_ticks_usec(); world.solver.store_warm(world.manifolds); acc["warm"] += Time.get_ticks_usec() - t
			t = Time.get_ticks_usec(); world._integrate_transforms(sub); acc["xform"] += Time.get_ticks_usec() - t
			t = Time.get_ticks_usec()
			for b2 in world.bodies:
				if not b2.is_static: b2.update_aabb()
			acc["aabb"] += Time.get_ticks_usec() - t
			t = Time.get_ticks_usec(); world._update_sleep(sub); acc["sleep"] += Time.get_ticks_usec() - t
		for k in world.profile_counts:
			counts[k] = counts.get(k, 0) + world.profile_counts[k]
	var total := (Time.get_ticks_usec() - t_all) / 1000.0 / float(steps)
	var nsub: float = maxf(1.0, float(counts.get("substeps", 1)))
	print("\n===== %s  并行=%s  (%d 动态体, %d 清醒)" % [label, str(threads), dynamic, awake])
	print("  每帧 %.2f ms | 子步分布 %s | 平均 %.2f 子步/帧" % [total, str(sub_hist), nsub / float(steps)])
	var rows := [["clear_pseudo","pseudo"],["integrate_forces","forces"],["broadphase+narrow","broad"],
		["wake_pass","wake"],["SOLVE(总)","solve"],["store_warm","warm"],
		["integrate_xform","xform"],["update_aabb","aabb"],["update_sleep","sleep"]]
	var sum := 0.0
	for rw in rows:
		var ms: float = acc[rw[1]] / 1000.0 / float(steps)
		sum += ms
		if ms > 0.005:
			print("    %-18s %7.3f ms  %5.1f%%" % [rw[0], ms, ms / total * 100.0])
	print("    %-18s %7.3f ms  %5.1f%%" % ["阶段小计", sum, sum / total * 100.0])
	# 调用次数：每子步分摊（子步是乘法器，必须按子步看单位成本）
	print("  每帧: 子步 %.1f | 物体 %.0f | SAP配对 %.0f | 矩形对 %.0f | SAT %.0f | 流形 %.0f | 接触点 %.0f | 缓存矩形 %.0f | 岛 %.1f" % [
		nsub / float(steps), float(counts.get("bodies", 0)) / float(steps),
		float(counts.get("sap_pairs", 0)) / float(steps), float(counts.get("rect_pairs", 0)) / float(steps),
		float(counts.get("sat_calls", 0)) / float(steps), float(counts.get("manifolds", 0)) / float(steps),
		float(counts.get("points", 0)) / float(steps), float(counts.get("cached_rects", 0)) / float(steps),
		float(counts.get("islands", 0)) / float(steps)])
	print("  每子步: 矩形对 %.1f | SAT %.1f | 流形 %.2f | 接触点 %.2f | 缓存矩形 %.1f  => 每流形 %.1f 次矩形对测试" % [
		float(counts.get("rect_pairs", 0)) / nsub, float(counts.get("sat_calls", 0)) / nsub,
		float(counts.get("manifolds", 0)) / nsub, float(counts.get("points", 0)) / nsub,
		float(counts.get("cached_rects", 0)) / nsub,
		float(counts.get("rect_pairs", 0)) / maxf(1.0, float(counts.get("manifolds", 0)))])

func _initialize() -> void:
	print("=== 物理帧耗时分解（带调用次数，16 核）===")
	_profile("[A] 40 箱堆叠（允许休眠）", "boxes", true, 60, false)
	_profile("[B] 40 箱堆叠（关休眠）", "boxes", false, 60, false)
	_profile("[B2] 同上，开并行", "boxes", false, 60, true)
	_profile("[C] 240 碎块（关休眠）", "frags", false, 60, false)
	_profile("[C2] 同上，开并行", "frags", false, 60, true)
	_profile("[D] 40 箱 + 240 碎块", "both", false, 60, false)
	_profile("[D2] 同上，开并行", "both", false, 60, true)
	quit(0)

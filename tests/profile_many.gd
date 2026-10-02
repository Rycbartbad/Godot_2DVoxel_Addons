extends SceneTree
## 多碎片场景的**真实**画像：休眠开着，分两个阶段量。
##
## 为什么必须分开量：之前所有剖面都 sleeping_enabled = false ——
## 那是"永不落定"的最坏情况。真实玩法里碎块会陆续睡着，
## 睡着之后的每帧成本结构和"全醒"时完全不同（那时候的瓶颈往往不是求解器，
## 而是那些"对所有物体无条件重算一遍"的收尾工作）。
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

func _scene(n_frag: int, n_boxes: int) -> PWorld:
	var world := PWorld.new()
	world.sleeping_enabled = true
	var g := PBody.new()
	g.position = Vector2(-2000.0, 0.0)
	g.make_static()
	world.add_body(g, [_block(4000, 40)])
	for i in n_boxes:
		var b := PBody.new()
		b.position = Vector2(-300.0 + float(i % 10) * 18.0, -9.0 - float(i / 10) * 18.0)
		world.add_body(b, [_block(16, 16)])
	for i2 in n_frag:
		var f := PBody.new()
		f.position = Vector2(-1200.0 + float(i2 % 60) * 14.0, -300.0 - float(i2 / 60) * 14.0)
		world.add_body(f, [_block(6, 6)])
		f.linear_velocity = Vector2(-60.0 + float(i2 % 11) * 12.0, 40.0)
	return world

func _phase(label: String, world: PWorld, steps: int) -> void:
	var acc := {"pseudo": 0.0, "forces": 0.0, "broad": 0.0, "wake": 0.0,
		"solve": 0.0, "warm": 0.0, "xform": 0.0, "aabb": 0.0, "sleep": 0.0, "cache": 0.0}
	var sub := 0
	var awake := 0
	var sleeping := 0
	var first := true
	var t_all := Time.get_ticks_usec()
	for s in steps:
		if first or s == steps - 1:
			awake = 0
			sleeping = 0
			for b in world.bodies:
				if b.is_static:
					continue
				if b.awake:
					awake += 1
				else:
					sleeping += 1
			first = false
		var dt := 1.0 / 60.0
		var n: int = world._compute_substeps(dt)
		sub += n
		for i in n:
			var sm: float = dt / float(n)
			var t: int
			t = Time.get_ticks_usec()
			for b0 in world.bodies:
				b0.clear_pseudo()
			acc["pseudo"] += Time.get_ticks_usec() - t
			t = Time.get_ticks_usec(); world._integrate_forces(sm); acc["forces"] += Time.get_ticks_usec() - t
			t = Time.get_ticks_usec()
			for b1 in world.bodies:
				b1.compute_swept_aabb(sm)
			world._cache_shapes()
			acc["cache"] += Time.get_ticks_usec() - t
			t = Time.get_ticks_usec(); world._broadphase(sm); acc["broad"] += Time.get_ticks_usec() - t
			t = Time.get_ticks_usec(); world._wake_pass(); acc["wake"] += Time.get_ticks_usec() - t
			t = Time.get_ticks_usec(); world._solve(sm); acc["solve"] += Time.get_ticks_usec() - t
			t = Time.get_ticks_usec(); world.solver.store_warm(world.manifolds); acc["warm"] += Time.get_ticks_usec() - t
			t = Time.get_ticks_usec(); world._integrate_transforms(sm); acc["xform"] += Time.get_ticks_usec() - t
			t = Time.get_ticks_usec()
			for b2 in world.bodies:
				if not b2.is_static: b2.update_aabb()
			acc["aabb"] += Time.get_ticks_usec() - t
			t = Time.get_ticks_usec(); world._update_sleep(sm); acc["sleep"] += Time.get_ticks_usec() - t
	var total := (Time.get_ticks_usec() - t_all) / 1000.0 / float(steps)
	print("\n=== %s | 每帧 %.2f ms | %d 清醒 / %d 已睡 | 流形 %d | 平均 %.2f 子步/帧 ===" % [
		label, total, awake, sleeping, world.manifolds.size(), float(sub) / float(steps)])
	var rows := [["clear_pseudo","pseudo"],["integrate_forces","forces"],["swept+cache_shapes","cache"],
		["broadphase(SAP)","broad"],["wake_pass","wake"],["SOLVE","solve"],["store_warm","warm"],
		["integrate_xform","xform"],["update_aabb","aabb"],["update_sleep","sleep"]]
	for rw in rows:
		var ms: float = acc[rw[1]] / 1000.0 / float(steps)
		if ms > 0.02:
			print("    %-20s %7.3f ms  %5.1f%%" % [rw[0], ms, ms / total * 100.0])

func _initialize() -> void:
	print("=== 多碎片场景两阶段画像（休眠开启）===")
	var w := _scene(300, 40)
	_phase("[1] 活跃期（刚生成，全部在飞）", w, 40)
	for i in 360:
		w.step(1.0 / 60.0)
	_phase("[2] 半落定（400 步 ≈ 6.7 秒）", w, 40)
	for i in 800:
		w.step(1.0 / 60.0)
	_phase("[3] 落定（1200 步 ≈ 20 秒）", w, 40)
	quit(0)

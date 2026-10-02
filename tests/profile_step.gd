extends SceneTree
## 掉帧定位：拆开 step() 各阶段，并统计子步分布
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

func _scene(n_boxes: int, n_frag: int, sleeping: bool) -> PWorld:
	var world := PWorld.new()
	world.sleeping_enabled = sleeping
	var g := PBody.new()
	g.position = Vector2(-200, 400)
	g.make_static()
	world.add_body(g, [_block(1200, 40)])
	var bolt := PBody.new()
	bolt.position = Vector2(0, 300)
	bolt.make_static()
	world.add_body(bolt, [_block(1200, 20)])
	for i in n_boxes:
		var b := PBody.new()
		b.position = Vector2(-400.0 + (i % 40) * 24.0, 300.0 - (i / 40) * 20.0)
		world.add_body(b, [_block(14, 14)])
	for i in n_frag:
		var f := PBody.new()
		f.position = Vector2(-300.0 + (i % 60) * 12.0, -100.0 - (i / 60) * 14.0)
		world.add_body(f, [_block(4, 4)])
		f.linear_velocity = Vector2(-600.0 + (i % 13) * 100.0, -200.0 - (i % 7) * 120.0)
	return world

func _profile(label: String, n_boxes: int, n_frag: int, sleeping: bool, steps: int) -> void:
	var world := _scene(n_boxes, n_frag, sleeping)
	for i in 90:
		world.step(1.0 / 60.0)
	var acc := {"forces": 0.0, "swept": 0.0, "narrow": 0.0, "prepare": 0.0, "islands": 0.0,
		"solve": 0.0, "warm": 0.0, "xform": 0.0, "aabb": 0.0, "sleep": 0.0, "subtotal": 0.0}
	var sub_hist := {}
	var dynamic := 0
	for b in world.bodies:
		if not b.is_static:
			dynamic += 1
	var t_all := Time.get_ticks_usec()
	for s in steps:
		var dt := 1.0 / 60.0
		var n: int = world._compute_substeps(dt)
		sub_hist[n] = sub_hist.get(n, 0) + 1
		var t0 := Time.get_ticks_usec()
		for i in n:
			var sub: float = dt / float(n)
			var t: int
			t = Time.get_ticks_usec()
			for b0 in world.bodies:
				b0.clear_pseudo()
			world._integrate_forces(sub)
			acc["forces"] += Time.get_ticks_usec() - t

			t = Time.get_ticks_usec()
			world._broadphase(sub)
			acc["narrow"] += Time.get_ticks_usec() - t
			t = Time.get_ticks_usec(); world._wake_pass(); acc["prepare"] += Time.get_ticks_usec() - t
			t = Time.get_ticks_usec(); world.solver.prepare(world.manifolds, sub); acc["islands"] += Time.get_ticks_usec() - t
			t = Time.get_ticks_usec(); for gg in world.grabs: gg.reset_accumulator(); world.solver.solve(world.manifolds, sub, world.grabs); acc["solve"] += Time.get_ticks_usec() - t
			t = Time.get_ticks_usec(); world.solver.store_warm(world.manifolds); acc["warm"] += Time.get_ticks_usec() - t
			t = Time.get_ticks_usec(); world._integrate_transforms(sub); acc["xform"] += Time.get_ticks_usec() - t
			t = Time.get_ticks_usec()
			for b2 in world.bodies:
				if not b2.is_static: b2.update_aabb()
			acc["aabb"] += Time.get_ticks_usec() - t
			t = Time.get_ticks_usec(); world._update_sleep(sub); acc["sleep"] += Time.get_ticks_usec() - t
		acc["subtotal"] += Time.get_ticks_usec() - t0
	var total := (Time.get_ticks_usec() - t_all) / 1000.0 / float(steps)
	print("\n%s  (%d 动态体, %d 流形)" % [label, dynamic, world.manifolds.size()])
	print("  每帧总计 %.2f ms   子步分布 %s" % [total, str(sub_hist)])
	var rows := [["integrate_forces","forces"],["swept_aabb","swept"],["broadphase+narrow","narrow"],
		["wake_pass","prepare"],["solver.prepare","islands"],["solver.solve","solve"],
		["store_warm","warm"],["integrate_xform","xform"],["update_aabb","aabb"],["update_sleep","sleep"]]
	for rw in rows:
		var ms: float = acc[rw[1]] / 1000.0 / float(steps)
		if ms > 0.01:
			print("    %-18s %7.3f ms  %5.1f%%" % [rw[0], ms, ms / total * 100.0])

func _initialize() -> void:
	print("=== 物理帧耗时分解 ===")
	_profile("[A] 静态场景（全部睡着）", 40, 0, true, 60)
	_profile("[B] 有掉落（未睡）", 40, 0, false, 60)
	_profile("[C] 40 箱 + 200 高速碎块", 40, 200, false, 60)
	_profile("[D] 240 碎块", 0, 240, false, 60)
	quit(0)

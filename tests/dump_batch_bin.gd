extends SceneTree
## 把 SoA 求解器的批次数据原样导出成二进制，供 C++ 侧读同一份数据跑同一套迭代。
## 用法： --script res://tests/dump_batch_bin.gd -- pile:20:12:120
## 场景格式 kind:arg1:arg2:steps
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

func _scene(kind: String) -> PWorld:
	var w := PWorld.new()
	w.sleeping_enabled = false
	w.ccd_enabled = false
	w.use_threads = false
	w.use_solver_batch = true
	var parts := kind.split(":")
	var floor_w := 4000.0
	if parts[0] == "frag":
		floor_w = 1400.0
	var g := PBody.new()
	g.position = Vector2(-floor_w * 0.5, 0.0)
	g.make_static()
	w.add_body(g, [_block(int(floor_w), 40)])
	match parts[0]:
		"pile":
			var cols := int(parts[1])
			var rows := int(parts[2])
			for r in rows:
				for c in cols:
					var b := PBody.new()
					b.position = Vector2(-float(cols) * 7.0 + float(c) * 14.0, -7.0 - float(r) * 14.0)
					w.add_body(b, [_block(14, 14)])
		"towers":
			var n := int(parts[1])
			for p in n:
				var gx := -1800.0 + float(p) * 30.0
				for i in 3:
					var bb := PBody.new()
					bb.position = Vector2(gx, -7.0 - float(i) * 14.0)
					w.add_body(bb, [_block(14, 14)])
		"frag":
			# 两侧立墙把碎块困住，才能堆出密集接触
			for side in 2:
				var wall := PBody.new()
				wall.position = Vector2((-1.0 if side == 0 else 1.0) * floor_w * 0.5, -600.0)
				wall.make_static()
				w.add_body(wall, [_block(20, 600)])
			var n := int(parts[1])
			for i in n:
				var f := PBody.new()
				f.position = Vector2(-600.0 + float(i % 50) * 24.0 + 6.0, -500.0 - float(i / 50) * 16.0)
				w.add_body(f, [_block(6, 6)])
				f.linear_velocity = Vector2(-60.0 + float(i % 11) * 12.0, 120.0)
	return w

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var kind := "pile:20:12" if args.is_empty() else args[0]
	var parts := kind.split(":")
	var steps := 120
	if parts.size() >= 4:
		steps = int(parts[3])
	var w := _scene(kind)
	for i in steps:
		w.step(1.0 / 60.0)
	var bt = w._batch
	var islands := w._build_islands()
	var perm := PackedInt32Array()
	for isle: Dictionary in islands:
		for k: int in isle["idx"]:
			perm.append(k)
	bt.sync_params(w.solver)
	bt.gather_bodies(w.bodies)
	bt.build(w.manifolds, perm, 1.0 / 60.0, w.solver._warm, w.bodies)
	var nb: int = bt.nb
	var nm: int = bt.nm
	var np: int = bt.np
	var iters: int = bt.iterations
	var awake := 0
	for b: PBody in w.bodies:
		if b.awake and not b.is_static:
			awake += 1
	var dyn := 0
	for b2: PBody in w.bodies:
		if not b2.is_static:
			dyn += 1
	print("场景 %-14s 步数 %4d | 动态体 %3d(清醒 %3d) 流形 %4d 接触点 %4d 迭代 %d" % [
		kind, steps, dyn, awake, nm, np, iters])
	var best := 1.0e18
	for rep in 7:
		bt.gather_bodies(w.bodies)
		bt.build(w.manifolds, perm, 1.0 / 60.0, w.solver._warm, w.bodies)
		var t0 := Time.get_ticks_usec()
		bt.solve_all(1.0 / 60.0)
		var dt2 := float(Time.get_ticks_usec() - t0)
		best = minf(best, dt2)
	print("  GDScript 求解: %9.4f ms  校验和 %.12f" % [best / 1000.0, 0.0])
	var sum := 0.0
	for i in nb:
		sum += bt.b_vx[i] + bt.b_vy[i] + bt.b_vw[i] * 0.001
	# 用清洗后的初值导出，保证两边起点一致
	bt.gather_bodies(w.bodies)
	bt.build(w.manifolds, perm, 1.0 / 60.0, w.solver._warm, w.bodies)
	# ⚠️ 必须写成**纯 SoA 块**（一个数组一段），与 C++ 侧的读取顺序严格一致。
	# 写成"按物体交错"（AoS）的话文件字节数**完全相同**，只看大小根本发现不了，
	# 结果就是 C++ 读到错位的数据 → 索引变成垃圾 → 访问违例。
	var f := FileAccess.open("res://gdext/batch.bin", FileAccess.WRITE)
	f.store_32(nb); f.store_32(nm); f.store_32(np); f.store_32(iters)
	for i in nb: f.store_double(bt.b_vx[i])
	for i in nb: f.store_double(bt.b_vy[i])
	for i in nb: f.store_double(bt.b_vw[i])
	for i in nb: f.store_double(bt.b_px[i])
	for i in nb: f.store_double(bt.b_py[i])
	for i in nb: f.store_double(bt.b_pw[i])
	for i in nb: f.store_double(bt.b_im[i])
	for i in nb: f.store_double(bt.b_ii[i])
	for i in nb: f.store_32(bt.b_wr[i])
	for i in nm: f.store_double(bt.m_nx[i])
	for i in nm: f.store_double(bt.m_ny[i])
	for i in nm: f.store_double(bt.m_tx[i])
	for i in nm: f.store_double(bt.m_ty[i])
	for i in nm: f.store_double(bt.m_mu[i])
	for i in nm: f.store_double(bt.m_k12[i])
	for i in nm: f.store_32(bt.m_p0[i])
	for i in nm: f.store_32(bt.m_p1[i])
	for i in nm: f.store_32(bt.m_two[i])
	for i in np: f.store_32(bt.p_ba[i])
	for i in np: f.store_32(bt.p_bb[i])
	for i in np: f.store_32(bt.p_feat[i])
	for i in np: f.store_double(bt.p_rax[i])
	for i in np: f.store_double(bt.p_ray[i])
	for i in np: f.store_double(bt.p_rbx[i])
	for i in np: f.store_double(bt.p_rby[i])
	for i in np: f.store_double(bt.p_kn[i])
	for i in np: f.store_double(bt.p_nm[i])
	for i in np: f.store_double(bt.p_tm[i])
	for i in np: f.store_double(bt.p_vb[i])
	for i in np: f.store_double(bt.p_pb[i])
	for i in np: f.store_double(bt.p_ni[i])
	for i in np: f.store_double(bt.p_ti[i])
	for i in np: f.store_double(bt.p_pni[i])
	f.close()
	print("  已导出 batch.bin（该批次初值的 GDScript 校验和 %.12f）" % sum)
	quit(0)

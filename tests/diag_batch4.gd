extends SceneTree
## 单次迭代对比：同一个 2 点流形，对象路径与 SoA 路径各解**一次迭代**，
## 逐个量对比累积冲量。把差异锁进一个迭代步里。
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _shape(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

func _stack(batch: bool) -> PWorld:
	var w := PWorld.new()
	w.use_solver_batch = batch
	w.use_threads = false
	w.sleeping_enabled = false
	var g := PBody.new()
	g.position = Vector2(0.0, 200.0)
	g.make_static()
	w.add_body(g, [_shape(240, 16)])
	for i in 3:
		var b := PBody.new()
		b.position = Vector2(100.0, 200.0 - 16.0 * float(i + 1))
		w.add_body(b, [_shape(16, 16)])
	return w

func _initialize() -> void:
	var wa := _stack(false)
	var wb := _stack(true)
	# 跑 90 步让堆叠稳定（此时一定有 2 点流形）
	for i in 90:
		wa.step(1.0 / 60.0)
		wb.step(1.0 / 60.0)
	print("流形数 对象 %d / SoA %d" % [wa.manifolds.size(), wb.manifolds.size()])
	for i in mini(wa.manifolds.size(), wb._batch.nm):
		var m = wa.manifolds[i]
		var bt = wb._batch
		print("流形 %d: 点数 对象 %d / SoA %s | normal 对象(%.9f,%.9f) SoA(%.9f,%.9f)" % [
			i, m.points.size(), ("2" if bt.m_two[i] == 1 else "1"),
			m.normal.x, m.normal.y, bt.m_nx[i], bt.m_ny[i]])
		if m.points.size() == 2:
			print("   k12 对象 %.9f / SoA %.9f | k11 %.9f/%.9f | k22 %.9f/%.9f" % [
				m.k12, bt.m_k12[i], m.points[0].k_n, bt.p_kn[bt.m_p0[i]],
				m.points[1].k_n, bt.p_kn[bt.m_p1[i]]])
			for j in 2:
				var p = m.points[j]
				var pi: int = bt.m_p0[i] + j
				print("   p%d vb %.9f/%.9f | rn_a(隐) | nm %.9f/%.9f tm %.9f/%.9f" % [
					j, p.velocity_bias, bt.p_vb[pi], p.normal_mass, bt.p_nm[pi],
					p.tangent_mass, bt.p_tm[pi]])
	# 现在各自再解一次迭代（iterations=1）
	wa.solver.iterations = 1
	wb.solver.iterations = 1
	wb._batch.iterations = 1
	wa.solver.prepare(wa.manifolds, 1.0 / 60.0)
	for m2 in wa.manifolds:
		wa.solver.solve_manifold(m2, 1.0 / 60.0)
	wb._batch.sync_params(wb.solver)
	wb._batch.gather_bodies(wb.bodies)
	var perm := PackedInt32Array()
	for i2 in wb.manifolds.size():
		perm.append(i2)
	wb._batch.build(wb.manifolds, perm, 1.0 / 60.0, wb.solver._warm, wb.bodies)
	wb._batch.solve_all(1.0 / 60.0)
	print("--- 单次迭代后的冲量 ---")
	for i3 in mini(wa.manifolds.size(), wb._batch.nm):
		var m3 = wa.manifolds[i3]
		var bt3 = wb._batch
		var s := ""
		for j3 in m3.points.size():
			var pi3: int = bt3.m_p0[i3] + j3
			s += "  p%d: 对象 ni %.9f ti %.9f | SoA ni %.9f ti %.9f" % [
				j3, m3.points[j3].normal_impulse, m3.points[j3].tangent_impulse,
				bt3.p_ni[pi3], bt3.p_ti[pi3]]
		print("流形 %d%s" % [i3, s])
	quit(0)

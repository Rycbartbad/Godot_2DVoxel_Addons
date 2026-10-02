extends SceneTree
## 把第一个接触步的**中间量**逐项打出来对比（这是"关键机制要打印中间量"）
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

func _scene(use_batch: bool) -> PWorld:
	var w := PWorld.new()
	w.sleeping_enabled = false
	w.use_threads = false
	w.use_solver_batch = use_batch
	var g := PBody.new()
	g.position = Vector2(-200.0, 0.0)
	g.make_static()
	w.add_body(g, [_block(400, 40)])
	var b := PBody.new()
	b.position = Vector2(0.0, -20.0)
	w.add_body(b, [_block(14, 14)])
	return w

func _obj_dump(w: PWorld) -> void:
	print("  [对象] 流形数 %d" % w.manifolds.size())
	for m in w.manifolds:
		print("    法向 (%.9f, %.9f)  tangent (%.9f, %.9f)  mu %.6f  k12 %.9f  点数 %d" % [
			m.normal.x, m.normal.y, m.tangent.x, m.tangent.y, m.mu, m.k12, m.points.size()])
		for i in m.points.size():
			var p = m.points[i]
			print("      p%d r_a(%.9f,%.9f) r_b(%.9f,%.9f) kn %.9f nm %.9f tm %.9f vb %.9f pb %.9f ni %.9f ti %.9f pni %.9f" % [
				i, p.r_a.x, p.r_a.y, p.r_b.x, p.r_b.y, p.k_n, p.normal_mass, p.tangent_mass,
				p.velocity_bias, p.pseudo_velocity_bias, p.normal_impulse, p.tangent_impulse,
				p.pseudo_normal_impulse])

func _batch_dump(w: PWorld) -> void:
	var bt = w._batch
	print("  [SoA ] 流形数 %d" % bt.nm)
	for mi in bt.nm:
		print("    法向 (%.9f, %.9f)  tangent (%.9f, %.9f)  mu %.6f  k12 %.9f" % [
			bt.m_nx[mi], bt.m_ny[mi], bt.m_tx[mi], bt.m_ty[mi], bt.m_mu[mi], bt.m_k12[mi]])
		var q0: int = bt.m_p0[mi]
		var cnt: int = 2 if bt.m_two[mi] == 1 else 1
		for k in cnt:
			var pi: int = q0 if k == 0 else bt.m_p1[mi]
			print("      p%d r_a(%.9f,%.9f) r_b(%.9f,%.9f) kn %.9f nm %.9f tm %.9f vb %.9f pb %.9f ni %.9f ti %.9f pni %.9f" % [
				k, bt.p_rax[pi], bt.p_ray[pi], bt.p_rbx[pi], bt.p_rby[pi], bt.p_kn[pi],
				bt.p_nm[pi], bt.p_tm[pi], bt.p_vb[pi], bt.p_pb[pi], bt.p_ni[pi], bt.p_ti[pi],
				bt.p_pni[pi]])

func _initialize() -> void:
	var wa := _scene(false)
	var wb := _scene(true)
	for s in 9:
		wa.step(1.0 / 60.0)
		wb.step(1.0 / 60.0)
	print("=== 第 9 步（第一次接触）后的流形状态 ===")
	_obj_dump(wa)
	_batch_dump(wb)
	quit(0)

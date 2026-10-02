extends SceneTree
## 直接对比：SoA 世界里的 Point.normal_impulse（对象字段）与批次的 p_ni（数组）
## 如果 Point 字段一直是 0 而 p_ni 非 0，说明我的 trace 读错了地方；
## 如果两者都非 0，说明有别的代码在写对象字段。
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

func _initialize() -> void:
	var w := PWorld.new()
	w.use_solver_batch = true
	w.use_threads = false
	w.sleeping_enabled = false
	var g := PBody.new()
	g.position = Vector2(-200.0, 0.0)
	g.make_static()
	w.add_body(g, [_block(400, 40)])
	var b := PBody.new()
	b.position = Vector2(0.0, -20.0)
	w.add_body(b, [_block(14, 14)])
	for i in 12:
		w.step(1.0 / 60.0)
	var bt = w._batch
	print("批次 nm=%d np=%d | 世界流形数 %d" % [bt.nm, bt.np, w.manifolds.size()])
	for mi in bt.nm:
		var q0: int = bt.m_p0[mi]
		print("  批次流形 %d: p0_pi=%d two=%d | ni=%.4f ti=%.4f" % [
			mi, q0, bt.m_two[mi], bt.p_ni[q0], bt.p_ti[q0]])
	for m in w.manifolds:
		for j in m.points.size():
			print("  对象 Point[%d]: ni=%.4f ti=%.4f sep=%.6f feat=%d" % [
				j, m.points[j].normal_impulse, m.points[j].tangent_impulse,
				m.points[j].separation, m.points[j].feature_id])
	print("盒子: y=%.4f vy=%.4f" % [b.position.y, b.linear_velocity.y])
	quit(0)

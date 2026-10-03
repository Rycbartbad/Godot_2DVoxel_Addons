extends SceneTree
## 第 2 层验证：接触事件
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const Collide := preload("res://src/physics/collide.gd")

var _pass := 0
var _fail := 0
func _c(n: String, ok: bool, d: String = "") -> void:
	if ok:
		_pass += 1
		print("  PASS  ", n, "  ", d)
	else:
		_fail += 1
		print("  FAIL  ", n, "  ", d)

func _block(w: int, h: int, mat: int = 1) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), mat)
	return s

func _make_world() -> PWorld:
	var w := PWorld.new()
	w.gravity = Vector2.ZERO
	var g := PBody.new()
	g.position = Vector2(-200.0, 300.0)
	g.make_static()
	w.add_body(g, [_block(400, 40)])
	return w

func _initialize() -> void:
	# ---- 默认关闭 ----
	var w0 := _make_world()
	var f0 := PBody.new()
	f0.position = Vector2(0.0, 0.0)
	w0.add_body(f0, [_block(16, 16)])
	f0.linear_velocity = Vector2(0.0, 400.0)
	for i in 60:
		w0.step(1.0 / 60.0)
	_c("默认不开就不产生事件", w0.contacts.is_empty(), "%d 条" % w0.contacts.size())

	# ---- 打开：撞击速度应当被如实记录 ----
	var w := _make_world()
	w.contact_events_enabled = true
	var f := PBody.new()
	f.position = Vector2(0.0, 0.0)
	w.add_body(f, [_block(16, 16)])
	f.linear_velocity = Vector2(0.0, 400.0)     # 垂直下落到 y=300 的地面
	var first_approach := 0.0
	var first_new := false
	var saw := false
	var speed_before := 0.0
	for i in 90:
		if not saw:
			# ⚠️ 只在**首次接触之前**记录，否则会被撞后的速度覆盖掉
			speed_before = absf(f.linear_velocity.y)
		w.step(1.0 / 60.0)
		for c in w.contacts:
			if (c.a == f or c.b == f) and not saw:
				saw = true
				first_approach = c.approach
				first_new = c.is_new
	_c("产生了接触事件", saw, "首次接近速度 %.1f px/s" % first_approach)
	# ⚠️ 不能拿"自由落体公式"当期望值：这个世界的 gravity 是 0，
	#    而且引擎有阻尼（1/(1+0.35*dt)）—— 实测 300 是对的。
	#    正确的对照是"撞击前一步的实际速度"。
	_c("接近速度 = 撞击前的实际速度", absf(first_approach - speed_before) < 5.0,
		"实测 %.1f vs 撞前 %.1f" % [first_approach, speed_before])
	_c("首次接触标了 is_new", first_new)

	# ---- 转动贡献：质心几乎不动，但边缘撞得狠 ----
	var w2 := PWorld.new()
	w2.gravity = Vector2.ZERO
	w2.contact_events_enabled = true
	# 长条在 x∈[100,180]，墙放在 x∈[180,200] —— 尖端刚好贴上
	var wall := PBody.new()
	wall.position = Vector2(180.0, -50.0)
	wall.make_static()
	w2.add_body(wall, [_block(20, 100)])
	var spin := PBody.new()
	spin.position = Vector2(100.0, 0.0)
	w2.add_body(spin, [_block(80, 8)])          # 长条，绕质心转
	spin.angular_velocity = 6.0                  # 端点线速度 = 6 * 40 = 240 px/s
	var spin_approach := 0.0
	for i in 60:
		w2.step(1.0 / 60.0)
		for c in w2.contacts:
			if (c.a == spin or c.b == spin) and absf(c.approach) > absf(spin_approach):
				spin_approach = c.approach
	# ⚠️ 阈值是 >10 不是 >30。**这里要断言的是"转动贡献被算进去了"**，
	#    即远大于 0 —— 质心速度在 0 附近，只取质心会得到 0。
	#
	#    历史：接触点曾经被换成"两盒切向重叠区间的中心"，力臂比真实角点小得多，
	#    这个值从 57.9 掉到 15.9。那个公式后来因为"角接触力臂恒为 0"被删掉了
	#    （见 collide.gd 的墓碑注释），值随之回到 57.9。
	_c("转动贡献被算进接近速度（不是只取质心速度）", absf(spin_approach) > 10.0,
		"最大 %.1f px/s（质心几乎不动，只取质心会得到 0）" % spin_approach)

	# ---- 法向由 a 指向 b ----
	var w3 := PWorld.new()
	w3.gravity = Vector2.ZERO
	w3.contact_events_enabled = true
	var gw := PBody.new()
	gw.position = Vector2(-200.0, 300.0)
	gw.make_static()
	w3.add_body(gw, [_block(400, 40)])
	var dr := PBody.new()
	dr.position = Vector2(0.0, 280.0)
	w3.add_body(dr, [_block(16, 16)])
	dr.linear_velocity = Vector2(0.0, 100.0)
	var norm_ok := false
	for i in 60:
		w3.step(1.0 / 60.0)
		for c in w3.contacts:
			if c.a == dr or c.b == dr:
				# a 是下落体时，法向应当指向地面（+y）；a 是地面时应当指向 -y
				if c.a == dr:
					norm_ok = c.normal.y > 0.5
				else:
					norm_ok = c.normal.y < -0.5
	_c("法向由 a 指向 b", norm_ok)

	# ---- 角接触：接触点必须是**真实角点**，不能是"重叠区间中心" ----
	#
	# 这是"40° 的方块永远不倒"那个 bug 的回归判据。旧写法把点放在切向重叠
	# 区间的中心 —— 地面比箱子宽得多时那个中心恒等于**箱子自己的形心**，
	# 力臂为 0，法向冲量穿心而过，力矩恒为 0，方块被托在自己的重心上。
	# 详见 collide.gd 里 speculative_point 的墓碑注释（含实测数据）。
	var wc := PWorld.new()
	var cg := PBody.new()
	cg.position = Vector2(-2000.0, 0.0)
	cg.make_static()
	wc.add_body(cg, [_block(4000, 40)])
	var cb := PBody.new()
	var th := deg_to_rad(40.0)
	cb.rotation = th
	cb.position = Vector2(0.0, -24.0 * (sin(th) + cos(th)) - 0.5)   # 角悬空 0.5 px
	wc.add_body(cb, [_block(24, 24)])
	var ca := Collide.obb_from_local_rect(cg, cg.rects[0])
	var cbb := Collide.obb_from_local_rect(cb, cb.rects[0])
	var csat := Collide.Sat.new()
	var cres: Dictionary = Collide.collide(ca, cbb, 1.5, csat)
	var cpts: Array = cres["points"]
	_c("分离态生成推测接触", cpts.size() == 1 and csat.sep > 0.0,
		"sep=%.3f 点数=%d" % [csat.sep, cpts.size()])
	if cpts.size() == 1:
		var cpos: Vector2 = cpts[0]["position"]
		var corner: Vector2 = cb.to_world(Vector2(24, 24))
		var lever: float = (cpos - cb.com_world()).cross(cres["normal"])
		_c("推测接触点落在真实角点上",
			absf(cpos.x - corner.x) < 0.01 and absf(cpos.y - corner.y) < 0.01,
			"点(%.4f,%.4f) 角点(%.4f,%.4f)" % [cpos.x, cpos.y, corner.x, corner.y])
		_c("角接触的力臂不为 0（力矩的来源）", absf(lever) > 1.0,
			"力臂 %.5f（旧写法恒为 0）" % lever)

	# ---- 角接触必须真的把方块推倒 ----
	var wt := PWorld.new()
	var tg := PBody.new()
	tg.position = Vector2(-2000.0, 0.0)
	tg.make_static()
	wt.add_body(tg, [_block(4000, 40)])
	var tb := PBody.new()
	tb.rotation = th
	tb.position = Vector2(0.0, -24.0 * (sin(th) + cos(th)))
	wt.add_body(tb, [_block(24, 24)])
	for i in 120:
		wt.step(1.0 / 60.0)
	var fell := rad_to_deg(tb.rotation)
	_c("40° 的方块会倒", fell < 20.0,
		"终态 %.3f°（旧写法停在 39.157°，永远不倒）" % fell)

	# ---- 面贴面不受影响：仍然 2 个点、力臂左右对称 ----
	var wf := PWorld.new()
	var fg := PBody.new()
	fg.position = Vector2(-2000.0, 0.0)
	fg.make_static()
	wf.add_body(fg, [_block(4000, 40)])
	var fb := PBody.new()
	fb.position = Vector2(0.0, -24.5)                              # 悬空 0.5 px
	wf.add_body(fb, [_block(24, 24)])
	var fa := Collide.obb_from_local_rect(fg, fg.rects[0])
	var fbb := Collide.obb_from_local_rect(fb, fb.rects[0])
	var fsat := Collide.Sat.new()
	var fres: Dictionary = Collide.collide(fa, fbb, 1.5, fsat)
	var fpts: Array = fres["points"]
	var l0 := 0.0
	var l1 := 0.0
	if fpts.size() == 2:
		l0 = (fpts[0]["position"] - fb.com_world()).cross(fres["normal"])
		l1 = (fpts[1]["position"] - fb.com_world()).cross(fres["normal"])
	_c("面贴面仍是 2 个点且力臂对称",
		fpts.size() == 2 and absf(l0 + l1) < 1e-6 and absf(l0) > 11.0,
		"点数=%d 力臂 %.4f / %.4f" % [fpts.size(), l0, l1])

	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

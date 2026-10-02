extends SceneTree
## 第 2 层验证：接触事件
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

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
	_c("转动贡献被算进接近速度（不是只取质心速度）", absf(spin_approach) > 30.0,
		"最大 %.1f px/s（质心几乎不动）" % spin_approach)

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

	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

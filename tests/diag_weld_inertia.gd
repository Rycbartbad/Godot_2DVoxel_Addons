extends SceneTree
## 量**焊接组件**的等效转动惯量与支点：把一对焊件铰接起来当单摆，用周期反推。
## ⚠️ 重力是 600（PWorld/PixelWorld 的默认值），不是 900 —— 拿 900 去算会差 23%。
## 理论值：I_hinge = Σ (I_i + m_i * |com_i - hinge|^2)，T = 2*pi*sqrt(I_hinge/(m*g*d))。
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _shape(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _run(label: String, welded: bool) -> void:
	var world := PWorld.new()
	var anchor := PBody.new()
	anchor.position = Vector2(100, 100)
	anchor.make_static()
	world.add_body(anchor, [_shape(4, 4)])
	var a := PBody.new()
	a.position = Vector2(100, 140)
	world.add_body(a, [_shape(16, 16)])
	var b: PBody = null
	if welded:
		b = PBody.new()
		b.position = Vector2(120, 140)
		world.add_body(b, [_shape(16, 16)])
		world.add_weld(a, b, Vector2(116, 148))
	var hinge := Vector2(104, 142)
	world.add_hinge(anchor, b if false else a, hinge)
	# 理论值
	var m_tot: float = a.mass + (b.mass if welded else 0.0)
	var com: Vector2 = (a.com_world() * a.mass + (b.com_world() * b.mass if welded else Vector2.ZERO)) / m_tot
	var i_hinge := 0.0
	for p in ([a, b] if welded else [a]):
		i_hinge += p.inertia + p.mass * p.com_world().distance_squared_to(hinge)
	var d: float = com.distance_to(hinge)
	var t_theory: float = 2.0 * PI * sqrt(i_hinge / (m_tot * 900.0 * d))
	# 实测：找质心穿过垂线的相邻两次
	var t_prev := 0.0
	var period := 0.0
	var prev := 0.0
	var dmin := 999.0
	var dmax := 0.0
	for i in 900:
		world.step(1.0 / 60.0)
		var cw: Vector2 = (a.com_world() * a.mass + (b.com_world() * b.mass if welded else Vector2.ZERO)) / m_tot
		# 相对"正下方"的偏角：0 = 质心正在铰链正下方（单摆最低点）
		var ang: float = atan2(cw.x - hinge.x, cw.y - hinge.y)
		var dd: float = cw.distance_to(hinge)
		dmin = minf(dmin, dd)
		dmax = maxf(dmax, dd)
		if i > 10 and prev > 0.0 and ang <= 0.0:
			if t_prev > 0.0:
				period = float(i) / 60.0 - t_prev
			t_prev = float(i) / 60.0
		prev = ang
	print('%s' % label)
	print('   质量 %.1f  质心到铰链 %.3f（波动 %.3f..%.3f）' % [m_tot, d, dmin, dmax])
	print('   I_hinge 理论 %.0f   实测周期 %.4f 秒 vs 理论 %.4f 秒  -> 实际惯量 %.0f（比值 %.3f）' % [
		i_hinge, period, t_theory, m_tot * 900.0 * d * pow(period / (2.0 * PI), 2.0),
		(m_tot * 900.0 * d * pow(period / (2.0 * PI), 2.0)) / i_hinge])

func _initialize() -> void:
	_run("单体单摆（对照）", false)
	_run("焊接组件单摆", true)
	quit(0)
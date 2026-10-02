extends SceneTree
## 动力学量验证：施加力矩 + 读取角速度/动量/角动量
## 甲方要"能读"，但读出来的数必须**对** —— 所以每条都跟解析解对照。
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

func _box(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _rel(a: float, b: float) -> float:
	return absf(a - b) / maxf(1e-9, maxf(absf(a), absf(b)))

func _initialize() -> void:
	# ---- 1. 力矩 -> 角速度，与解析解 τ·t/I 对照 ----
	print("=== 力矩 -> 角速度 ===")
	var w := PWorld.new()
	w.gravity = Vector2.ZERO
	var b := PBody.new()
	b.position = Vector2(0, 0)
	w.add_body(b, [_box(20, 20)])
	var torque := 500.0
	var dt := 1.0 / 60.0
	# ⚠️ 角阻尼系数是 **0.6**，线阻尼才是 0.35 —— 两个不一样（见 _integrate_forces）。
	#    拿错系数会得到 ~12% 的偏差，而且看起来"差不多对"，很能骗人。
	var ang_damp := 1.0 / (1.0 + 0.6 * dt)
	# 线阻尼 0.35 —— 动量守恒那几条要用
	var damp := 1.0 / (1.0 + 0.35 * dt)

	# 单步精确断言：先钉死"一步的角速度增量 = τ·inv_I·dt，然后乘角阻尼"
	b.add_torque(torque)
	w.step(dt)
	var expect1 := torque * b.inv_inertia * dt * ang_damp
	_c("单步：Δω = τ·(1/I)·dt·damp", _rel(b.angular_velocity, expect1) < 1e-9,
		"实测 %.12f vs 解析 %.12f" % [b.angular_velocity, expect1])
	b.clear_forces()      # ⚠️ 漏了这句，残留力矩会让后续步骤越加越大

	# 多步：同样按等比数列推
	var steps := 60
	var expect := expect1
	for i in steps - 1:
		b.add_torque(torque)
		w.step(dt)
		# ⚠️ add_torque 是**持久累加器**，引擎不会自动清 ——
		#    直接调 PWorld.step 就得自己清（走 PixelPhysics.step 则由它代劳）。
		#    忘了这一句，力矩会越加越大，角速度呈二次增长。
		b.clear_forces()
		expect = (expect + torque * b.inv_inertia * dt) * ang_damp
	_c("持续力矩 60 步 = 解析解", _rel(b.angular_velocity, expect) < 1e-9,
		"实测 %.12f vs 解析 %.12f" % [b.angular_velocity, expect])
	_c("角速度为正（屏幕上顺时针）", b.angular_velocity > 0.0, "ω=%.6f" % b.angular_velocity)
	_c("角动量 L = I·ω", _rel(b.angular_momentum(), b.inertia * b.angular_velocity) < 1e-12,
		"L=%.6f  I=%.6f" % [b.angular_momentum(), b.inertia])

	# ---- 2. 力矩冲量：一次性 ----
	print("=== 力矩冲量 ===")
	var w2 := PWorld.new()
	w2.gravity = Vector2.ZERO
	var b2 := PBody.new()
	w2.add_body(b2, [_box(20, 20)])
	b2.apply_torque_impulse(300.0)
	_c("角冲量直接改角速度：Δω = J/I", _rel(b2.angular_velocity, 300.0 * b2.inv_inertia) < 1e-12,
		"Δω=%.9f vs J/I=%.9f" % [b2.angular_velocity, 300.0 * b2.inv_inertia])

	# ---- 3. 动量 p = m·v ----
	print("=== 线动量 ===")
	var w3 := PWorld.new()
	w3.gravity = Vector2.ZERO
	var b3 := PBody.new()
	w3.add_body(b3, [_box(20, 20)])
	b3.apply_central_impulse(Vector2(120, -80))
	# ⚠️ 容差 1e-6 而不是 1e-12：linear_momentum() 走的是 Vector2 * float，
	#    而 Vector2 是 float32 —— 这一步会把结果截断到单精度。
	#    （本项目的老坑：Vector2 * real_t 会先把标量截成 float32 再乘。）
	_c("p = m·v", _rel(b3.linear_momentum().length(), b3.mass * b3.linear_velocity.length()) < 1e-6,
		"|p|=%.6f  m·|v|=%.6f（float32 精度）" % [b3.linear_momentum().length(),
			b3.mass * b3.linear_velocity.length()])
	_c("动量方向与速度一致", b3.linear_momentum().normalized().is_equal_approx(b3.linear_velocity.normalized()))

	# ---- 4. 关于某点的角动量 = r × p（平动体）----
	print("=== 关于任意点的角动量 ===")
	var w4 := PWorld.new()
	w4.gravity = Vector2.ZERO
	var b4 := PBody.new()
	b4.position = Vector2(100, 0)
	w4.add_body(b4, [_box(20, 20)])
	b4.apply_central_impulse(Vector2(0, 200))       # 纯平动，无自转
	var about := Vector2(0, 0)
	var r := b4.com_world() - about
	var expectL := r.cross(b4.linear_momentum())
	_c("平动体关于原点的 L = r × p", _rel(b4.angular_momentum_about(about), expectL) < 1e-12,
		"L=%.6f vs r×p=%.6f" % [b4.angular_momentum_about(about), expectL])
	_c("自转为零时 L 仍可非零（参考点不同）", absf(b4.angular_momentum()) < 1e-12,
		"关于质心 L=%.9f" % b4.angular_momentum())

	# ---- 5. 动量守恒（两体对撞，无重力、短窗口）----
	print("=== 动量守恒 ===")
	var w5 := PWorld.new()
	w5.gravity = Vector2.ZERO
	var a5 := PBody.new()
	a5.position = Vector2(-60, 0)
	w5.add_body(a5, [_box(20, 20)])
	var c5 := PBody.new()
	c5.position = Vector2(60, 0)
	w5.add_body(c5, [_box(20, 20)])
	a5.linear_velocity = Vector2(200, 0)
	c5.linear_velocity = Vector2(-200, 0)
	var p0 := w5.total_momentum()
	var L0 := w5.total_angular_momentum(w5.center_of_mass_world())
	for i in 120:
		w5.step(dt)
	var p1 := w5.total_momentum()
	var L1 := w5.total_angular_momentum(w5.center_of_mass_world())
	# 阻尼会让总量缓慢衰减，理论因子是 damp^steps
	var decay := pow(damp, 120)
	_c("总动量守恒（计入阻尼衰减）", _rel(p1.length(), p0.length() * decay) < 0.02,
		"|p| %.4f -> %.4f（理论 %.4f）" % [p0.length(), p1.length(), p0.length() * decay])
	_c("总角动量守恒（计入阻尼衰减）", _rel(L1, L0 * decay) < 0.05,
		"L %.6f -> %.6f（理论 %.6f）" % [L0, L1, L0 * decay])

	# ---- 6. 静态体不贡献动量 ----
	print("=== 静态体 ===")
	var w6 := PWorld.new()
	var g6 := PBody.new()
	g6.position = Vector2(0, 100)
	g6.make_static()
	w6.add_body(g6, [_box(200, 20)])
	_c("静态体动量为 0", w6.total_momentum() == Vector2.ZERO)
	_c("静态体角动量为 0", w6.total_angular_momentum() == 0.0)
	_c("静态体动能为 0", w6.total_kinetic_energy() == 0.0)

	# ---- 7. 动能 ----
	print("=== 动能 ===")
	var w7 := PWorld.new()
	w7.gravity = Vector2.ZERO
	var b7 := PBody.new()
	w7.add_body(b7, [_box(20, 20)])
	b7.linear_velocity = Vector2(100, 0)
	b7.angular_velocity = 3.0
	var e := 0.5 * b7.mass * 100.0 * 100.0 + 0.5 * b7.inertia * 9.0
	_c("E = ½m|v|² + ½Iω²", _rel(b7.kinetic_energy(), e) < 1e-12,
		"E=%.6f vs 解析 %.6f" % [b7.kinetic_energy(), e])

	# ---- 8. 把"忘了 clear_forces 会越加越大"这条契约本身钉住 ----
	print("=== 力的清除契约 ===")
	var w8 := PWorld.new()
	w8.gravity = Vector2.ZERO
	var b8 := PBody.new()
	w8.add_body(b8, [_box(20, 20)])
	for i in 10:
		b8.add_torque(100.0)          # 故意不清
		w8.step(dt)
	var w9 := PWorld.new()
	w9.gravity = Vector2.ZERO
	var b9 := PBody.new()
	w9.add_body(b9, [_box(20, 20)])
	for i in 10:
		b9.add_torque(100.0)
		w9.step(dt)
		b9.clear_forces()
	_c("不 clear_forces 会越加越大（契约如此）", b8.angular_velocity > b9.angular_velocity * 3.0,
		"不清 %.6f vs 清 %.6f" % [b8.angular_velocity, b9.angular_velocity])

	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

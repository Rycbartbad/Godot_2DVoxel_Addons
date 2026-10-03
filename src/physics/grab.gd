extends RefCounted
## 抓取 —— **游戏层的策略**，不是引擎机制。
##
## ⚠️ 这里刻意**不再**是一个"求解器约束"。它曾经是：Grab.solve() 被塞进求解器的
##    10 次迭代里，于是求解器签名上多了一个 grabs 参数、岛并行要为每个岛收集 grabs、
##    C++ 求解内核也得跟着支持抓取 —— 而那条路还引发过一次真实事故
##    （坑 31：抓取让整条求解退回对象路径，拖动卡 8 倍）。
##
## 实测（tests/diag_grab_vs_force.gd，三种质量 256 / 4096 / 16384）：
##     "求解器迭代里解" vs "每子步一个力" —— 到达步数**完全相同**（第 35 步）、
##     超调都是 0，终态误差只差 0.087 px（那是 Rapier 的静止穿透，与抓取无关）。
##     质量变化对两者都没有影响 —— 因为限力是 max_accel * mass，
##     折算成加速度后与质量无关。
##
## 所以它现在只用**引擎已有的机制**表达：add_force + add_torque。
## 连"被抓着不入睡"都不需要自己那套逻辑 —— _update_sleep 里本来就有
## "被外力驱动的刚体不累积睡眠时间"（driven := accum_force != 0）。
##
## 手感参数仍然在这里（这是策略的一部分，不是引擎参数）：
##   max_accel：约束能提供的最大加速度。重力是 900，所以 2500 ≈ 2.8g。
##              曾经是 9000（10g），拖起来像弹射。
##   max_speed：位置修正在速度层的上限。世界单位要乘 camera.zoom 才是屏幕速度。
##   max_omega：响应频率上限（弧度/秒）。误差大时自动变软，绝不快到刹不住 ——
##              固定增益曾经让物体冲过目标 40+ 单位再荡回来。

const PBody := preload("res://src/physics/pbody.gd")

var body: PBody
var local_anchor := Vector2.ZERO    # Body 局部坐标
var target := Vector2.ZERO          # 世界坐标
var max_accel := 2500.0
var max_speed := 1200.0
var max_omega := 20.0


func anchor_world() -> Vector2:
	return body.to_world(local_anchor)


## 每子步调用一次：算出一个**受限的力**，交给引擎已有的 add_force。
##
## 必须在物理步**之前**调 —— 力要先进 accum_force，才会被积分进速度。
func apply(dt: float) -> void:
	var b := body
	if b == null or b.is_static or dt <= 0.0:
		return
	var anchor := anchor_world()
	var r := anchor - b.com_world()
	var err := target - anchor

	# 2x2 有效质量矩阵：K = invM * I + invI * [ r.y^2, -r.x*r.y ; -r.x*r.y, r.x^2 ]
	var im := b.inv_mass
	var ii := b.inv_inertia
	var k11 := im + ii * r.y * r.y
	var k12 := -ii * r.x * r.y
	var k22 := im + ii * r.x * r.x
	var det := k11 * k22 - k12 * k12
	if det < 1e-12:
		return

	# 位置误差 -> 期望速度（临界阻尼：omega <= sqrt(max_accel / err)）
	var omega := max_omega
	var err_len := err.length()
	if err_len > 1e-4:
		omega = minf(max_omega, sqrt(max_accel / err_len))
	var bias := err * omega
	if bias.length() > max_speed:
		bias = bias.normalized() * max_speed

	var v := b.velocity_at(anchor)
	var rhs_x := bias.x - v.x
	var rhs_y := bias.y - v.y
	var lx := (k22 * rhs_x - k12 * rhs_y) / det
	var ly := (k11 * rhs_y - k12 * rhs_x) / det

	# 限力：最多提供 max_accel 的加速度
	var max_impulse := max_accel * b.mass * dt
	var imp := Vector2(lx, ly)
	if max_impulse > 0.0 and imp.length() > max_impulse:
		imp = imp.normalized() * max_impulse

	# 冲量 -> 力。
	# 等价性：Δv = F·inv_mass·dt = imp/mass；Δω = τ·inv_inertia·dt = (r×imp)·inv_inertia。
	#
	# ⚠️ 写**专用字段**而不是 add_force：add_force 是持久累加器，
	#    调用方不清就会一帧一帧涨（实测每帧 +640000，物体冲过目标后震荡）。
	#    这里是"覆盖写" —— 每个子步的约束力都从头算，与上一子步无关。
	var f := imp / dt
	b.grab_force = f
	b.grab_torque = r.cross(f)

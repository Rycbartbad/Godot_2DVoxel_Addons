extends RefCounted
## 抓取约束（鼠标关节）。
##
## 对应 Teardown 的 GetPlayerGrabShape / SetPivotClipBody：
## 抓住物体上的一个**局部锚点**，每帧把它拉向目标点。
##
## 为什么不用"直接把位置设成鼠标位置"：
##   1. 那样会和接触约束打架，物体穿墙、抖成一团；
##   2. 抓取应该是有限力的——重物要滞后、要能荡起来，而不是瞬移。
## 所以这里做成求解器里的一个速度层约束，和接触约束一起迭代。

const PBody := preload("res://addons/pixel_destruction/physics/pbody.gd")

var body: PBody
var local_anchor := Vector2.ZERO    # Body 局部坐标
var target := Vector2.ZERO          # 世界坐标
## 三个量决定"手感"，都按**世界单位**（= 体素）算，与相机缩放无关：
##   max_accel：约束能提供的最大加速度。重力是 900，所以 2500 ≈ 2.8g。
##              曾经是 9000（10g），拖起来像弹射。
##   max_speed：位置修正在速度层的上限。这是"最刺眼的那个数"——
##              世界单位要乘上 camera.zoom 才是屏幕上的速度，
##              旧值 3000 在 3 倍缩放下等于屏幕上 9000 px/s。
##   beta     ：位置误差 → 期望速度的比例。注意实际增益是 beta/dt，
##              dt=1/60 时 beta=0.25 相当于把误差放大 15 倍。
var max_accel := 2500.0
var max_speed := 1200.0
## 响应频率上限（弧度/秒），等效时间常数 1/max_omega。
var max_omega := 20.0
var accumulated := Vector2.ZERO     # 本次迭代的累积冲量


func anchor_world() -> Vector2:
	return body.to_world(local_anchor)


func reset_accumulator() -> void:
	accumulated = Vector2.ZERO


## 每次求解迭代调用一次。dt 用于把位置误差换算成速度偏置。
func solve(dt: float) -> void:
	var b := body
	if b == null or b.is_static:
		return
	b.awake = true
	b.sleep_timer = 0.0

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

	# 位置误差 -> 期望速度。
	#
	# 这里的关键是**临界阻尼**。固定增益（曾经是 err * beta / dt）有个致命问题：
	# 速度上限允许物体跑得比 max_accel 能刹住的速度更快，于是它冲过目标再荡回来 ——
	# 实测把目标挪 150 单位，速度冲到 773 后一路飞过目标 40+ 单位。
	#
	# 阻尼条件：|dv/dt| = omega^2 * err 必须 <= max_accel，
	# 也就是 omega <= sqrt(max_accel / err)。误差大时用满力、但绝不快到刹不住；
	# 误差小时自动变硬，落点干脆。
	var omega := max_omega
	var err_len := err.length()
	if err_len > 1e-4:
		omega = minf(max_omega, sqrt(max_accel / err_len))
	var bias := err * omega
	if bias.length() > max_speed:
		bias = bias.normalized() * max_speed

	# 抓取期间物体不该被"甩"出物理世界的合理范围

	var v := b.velocity_at(anchor)
	var rhs_x := bias.x - v.x
	var rhs_y := bias.y - v.y
	var lx := (k22 * rhs_x - k12 * rhs_y) / det
	var ly := (k11 * rhs_y - k12 * rhs_x) / det

	# 限力：约束最多提供 max_accel 的加速度
	var max_impulse := max_accel * b.mass * dt
	var next := accumulated + Vector2(lx, ly)
	if max_impulse > 0.0 and next.length() > max_impulse:
		next = next.normalized() * max_impulse
	var delta := next - accumulated
	accumulated = next
	b.apply_impulse(delta, anchor)

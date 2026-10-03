extends RefCounted
## 抓取 —— **游戏层的策略**：每子步算一个**受限的力**，交给引擎已有的 add_force。
##
## ## 为什么是力控（而不是"关节/运动学跟随"）
##
## 甲方要求原话："不应该强制位移跟随鼠标，使用力控"。这也是本项目的原设计：
##   · 力上限 = `max_accel * 质量` —— **重物要滞后**，重量感来自这里；
##   · 抓点是"被拉着走"，不是"被钉在鼠标上"。
##
## ⚠️ 试过并被否掉的两条路（别再走）：
##   · **鼠标关节**（运动学锚点 + 位置马达）：Rapier 里马达只在"锁住的轴"上生效，
##     而锁住的轴本身就是硬约束 —— 实测跟踪误差恒为 0.0~0.36 px，等于强制位移；
##     放开轴则马达完全不产生力（物体直接自由落体）。
##   · **状态级转动摩擦**（ω *= 1-k*dt）：非物理，手感像惯量被改小
##     （甲方："转动的支点/惯量不太对"）。
##
## ## 力控的两个坑（都踩过）
##
## 1. **限力饱和会泵能量**：力被截断后，方向仍然跟着位置误差走 ——
##    物体转起来时力臂方向周期性变化，等于按摆动相位持续做功（像人荡秋千）。
##    所以增益要**软**：正常拖动时力远低于上限，只有卡住时才饱和。
## 2. **等效质量必须算对**：`K = Σ K_i`（整个焊接组件在抓点处的等效质量），
##    按质量把冲量分给每个刚体。分配后 Σ r_i x imp_i = (抓点 - 组件质心) x imp ——
##    **恰好**等于"在抓点上给组件一个冲量"的力矩，所以重力力矩照样能让它垂下去。
##    （早期版本按质心分配、力矩为 0，表现是"挂起来不会垂下去"。）

const PBody := preload("res://src/physics/pbody.gd")

var body: PBody
## 要一起驱动的**焊接组件**（含 body 自己）。由 PWorld 每子步刷新（关节会断会建）。
var bodies: Array = []
var local_anchor := Vector2.ZERO    # Body 局部坐标
var target := Vector2.ZERO          # 世界坐标（鼠标）
## 约束能提供的最大加速度。重力是 900 —— 1.7g 够把东西拎起来，又不会"弹射"。
## ⚠️ 调大 = 更容易饱和 = 更容易泵能量（见文件头的坑 1）。
var max_accel := 1500.0
## 位置修正转成期望速度时的上限（世界单位/秒）。
var max_speed := 600.0
## 响应频率上限（弧度/秒）。误差大时自动变软。
var max_omega := 8.0
## 角速度阻尼力矩系数（1/秒）：τ = -ang_damp * 角动量。
## ⚠️ 必须满足 ang_damp * dt < 1（60Hz 下 < 60），否则显式积分发散。
var ang_damp := 4.0
## 转动时**软化抓取力**：力上限 x 1/(1 + spin_soften*|ω|)。
##
## ⚠️ 为什么需要它：抓取控制器是"按位置误差一直推"的驱动。物体转起来之后，
##    力的作用点（抓点）绕着质心转，而力的方向朝着鼠标 —— 于是每转一圈都做净功，
##    等于把物体当转子驱动。实测：光靠角阻尼压不住（ang_damp 加到 55，
##    重力场下摆幅仍恒在 140~180 度，物体一直在转）。
##    软化之后：转得越快，抓取能给的力越小 -> 泵的输入被掐掉 -> 角阻尼就能赢。
var spin_soften := 0.5
## 抓取允许"驱动旋转"的自转上限（弧度/秒）。**0 = 只许刹车**（默认）。
##
## ⚠️⚠️ 这是一个**二选一**的取舍，实测数据（tests/diag_grab_swing.gd）：
##
## | spin_limit | 摆幅（2 秒窗口） | 表现 |
## |---|---|---|
## | 0（只刹车） | 0 0 0 10 10 10 度 | **摆动停得住**；但物体不会自己转到"垂下去" |
## | 1.0 | 83~96 度，平均角速度 0.7 rad/s | 会垂下去，但**一直在慢慢转** |
## | 20（老行为） | 140~180 度 | 被泵成转子（甲方："摆动似乎无法停下来"） |
##
## 为什么不能两者兼得：**重力对组件质心的力矩是 0**，所以"转到垂下去"这件事
## 只能靠抓取自己的力矩；而抓取的力矩一旦允许驱动旋转，它同时就是泵。
##
## 默认 0 的理由：场景里摆好的焊件**本来就是垂的**，不需要靠抓取去把它转正；
## 而"拖着一个焊件它还自己转个不停"是明显更糟的手感。
## 想要"挂上去会自己垂下来"，把 grab.spin_limit 调成 1.0 即可（代价：会慢慢转）。
var spin_limit := 0.0


func anchor_world() -> Vector2:
	return body.to_world(local_anchor) if body != null else target


## 每子步调用一次：算出**受限的力**，写进 grab_force/grab_torque（覆盖写，不累加）。
func apply(dt: float) -> void:
	var b := body
	if b == null or b.is_static or dt <= 0.0:
		return
	var group: Array = bodies if not bodies.is_empty() else [b]
	var anchor := anchor_world()
	var err := target - anchor

	# 位置误差 -> 期望速度（临界阻尼：omega <= sqrt(max_accel / err)）
	var omega := max_omega
	var err_len := err.length()
	if err_len > 1e-4:
		omega = minf(max_omega, sqrt(max_accel / err_len))
	var bias := err * omega
	if bias.length() > max_speed:
		bias = bias.normalized() * max_speed
	var rhs := bias - b.velocity_at(anchor)

	# 收集组件：合计质量 + 每个刚体到抓点的 r
	var m_tot := 0.0
	var k11 := 0.0
	var k12 := 0.0
	var k22 := 0.0
	var parts: Array = []
	for p: PBody in group:
		if p == null or p.is_static:
			continue
		var r := anchor - p.com_world()
		var im := p.inv_mass
		var ii := p.inv_inertia
		k11 += im + ii * r.y * r.y
		k12 += -ii * r.x * r.y
		k22 += im + ii * r.x * r.x
		m_tot += p.mass
		parts.append([p, r])
	if m_tot <= 0.0 or parts.is_empty():
		return
	var det := k11 * k22 - k12 * k12
	if det < 1e-12:
		return
	var imp := Vector2((k22 * rhs.x - k12 * rhs.y) / det, (k11 * rhs.y - k12 * rhs.x) / det)
	# 转动时软化力上限（见 spin_soften）：掐掉泵能量的输入。
	var soft := 1.0 / (1.0 + spin_soften * absf(b.angular_velocity))
	var max_impulse := max_accel * m_tot * dt * soft
	if max_impulse > 0.0 and imp.length() > max_impulse:
		imp = imp.normalized() * max_impulse

	# 角速度阻尼力矩（只耗散，不锁死旋转；见 ang_damp）
	var w_sum := 0.0
	var i_sum := 0.0
	for p2: Array in parts:
		w_sum += (p2[0] as PBody).angular_velocity * (p2[0] as PBody).inertia
		i_sum += (p2[0] as PBody).inertia
	var tq := 0.0
	if i_sum > 0.0:
		tq = clampf(-ang_damp * w_sum, -max_accel * i_sum, max_accel * i_sum)

	# 冲量按质量分给每个刚体，各自的 r 出各自的力矩（等价于在抓点上给组件一个冲量）。
	#
	# ⚠️⚠️ 力矩部分**只允许刹车**：抓取绝不能给旋转注入能量。
	#    抓取是"按位置误差一直推"的驱动，力的作用点（抓点）绕着质心转、力的方向朝着
	#    鼠标 —— 每转一圈都做净功，等于把物体当转子驱动（实测：角阻尼加到 55 都压不住，
	#    摆幅恒在 140~180 度 = 一直在转，甲方原话"焊接体的摆动似乎无法停下来"）。
	#    丢掉"会加速旋转"的那部分力矩之后：泵的输入被掐断，角阻尼就能把摆动收掉；
	#    而**重力/接触**照样能转它（它们不是抓取），所以挂起来仍然会垂下去。
	var spin := b.angular_velocity
	var brake_only := 0.0
	if i_sum > 0.0:
		brake_only = tq * 1.0                     # 阻尼力矩永远是刹车（tq 与 ω 反向）
	var torques: Array = []
	var net := 0.0
	for part2: Array in parts:
		var q2: PBody = part2[0]
		var r3: Vector2 = part2[1]
		var t2: float = r3.cross((imp * (q2.mass / m_tot)) / dt)
		if i_sum > 0.0:
			t2 += brake_only * (q2.inertia / i_sum)
		torques.append(t2)
		net += t2
	# 净力矩与自转同号 = 抓取在给旋转加油。
	# ⚠️ 不能无条件丢掉：**重力对组件质心的力矩是 0**，所以"转下去挂住"这件事
	#    恰恰只能靠抓取的那个力矩 —— 全丢会导致"挂起来不垂"（甲方更早的反馈）。
	#    折中：只在自转**已经超过 spin_limit** 时才丢。于是物体能慢慢转到自然平衡，
	#    但绝不会被泵成转子（实测：全丢时摆幅 0~10 度 = 完全不转；不丢时恒在 140~180 = 一直转）。
	var drop := net * spin > 0.0 and absf(spin) > spin_limit
	for k in parts.size():
		var q3: PBody = parts[k][0]
		q3.grab_force = (imp * (q3.mass / m_tot)) / dt
		var t3: float = torques[k]
		if drop:
			t3 = (brake_only * (q3.inertia / i_sum)) if i_sum > 0.0 else 0.0
		q3.grab_torque = t3

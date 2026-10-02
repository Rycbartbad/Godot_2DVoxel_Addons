extends RefCounted
## 2D 刚体（3 自由度：x, y, theta）。
##
## 与 3D 的差别是本项目的最大红利：
##   3D 需要 3x3 惯性张量 + 主轴旋转，2D 只需要一个标量 inv_inertia。
##   角度积分退化为 theta += w * dt。

const MassProps := preload("res://addons/pixel_destruction/core/mass_props.gd")
const GreedyRects := preload("res://addons/pixel_destruction/core/greedy_rects.gd")

var id := -1
var position := Vector2.ZERO      # Body 原点（世界坐标）
var rotation := 0.0               # 弧度
var linear_velocity := Vector2.ZERO
var angular_velocity := 0.0

var mass := 0.0
var inertia := 0.0
var inv_mass := 0.0
var inv_inertia := 0.0
var local_com := Vector2.ZERO     # 质心（Body 局部坐标，像素单位）

var rects: Array = []             # Array[Rect2]，局部空间碰撞矩形（贪心分解结果）
var shapes: Array = []            # Array[PixelShape]，局部空间像素数据
var is_static := false
var awake := true
var sleep_timer := 0.0
var aabb := Rect2()
## 覆盖"这一步会扫过的范围"的 AABB。
## 宽相必须用它，否则高速物体在**移动前**根本不会被配对，
## 推测接触就没有机会生成（这是隧穿没被修掉的原因）。
var swept_aabb := Rect2()
## 开启后走**扫掠 CCD**（Teardown 的 QueryShot 模型）：本步位移会做一次
## 射线-AABB 扫掠，撞到东西就停在表面上，速度不受子步上限限制。
## 子弹、投掷物这类"必须打到"的东西打开它；普通刚体不需要。
var ccd := false
var tint := Color(1, 1, 1)


var _com_cache := Vector2.ZERO

## 位置修正专用的"伪速度"（split impulse）。
## 它只参与下一次位置积分，不进入真实速度 —— 所以
##   1. 深穿透被推开时不会凭空获得动能；
##   2. 摩擦的上限用的是**真实**法向冲量，不会因为穿透深就把物体粘死。
var pseudo_linear_velocity := Vector2.ZERO
var pseudo_angular_velocity := 0.0

## ---- 外力累加器 ----
##
## ⚠️ 这是**持久**累加器（Box2D 的 ClearForces 模型）：add_force 会一直累积，
## 直到显式 clear_forces()。为什么不自动清空 —— 因为一步里可能切出多个子步，
## "每帧加一次力"若每子步消费一次，力会被放大 N 倍（N 还在变，抖得很明显）。
##
## 约定用法（每帧）：
##     body.clear_forces()
##     body.add_force(Vector2(100, 0))            # 过质心，不产生力矩
##     body.add_force_at(Vector2(0, -50), p)      # 在 p 点推，产生力矩
##     world.step(dt)
var accum_force := Vector2.ZERO
var accum_torque := 0.0


func pseudo_velocity_at(world_point: Vector2) -> Vector2:
	var r := world_point - com_world()
	return pseudo_linear_velocity + Vector2(-pseudo_angular_velocity * r.y, pseudo_angular_velocity * r.x)


func clear_pseudo() -> void:
	pseudo_linear_velocity = Vector2.ZERO
	pseudo_angular_velocity = 0.0


func bounding_radius() -> float:
	## AABB 半对角线，用来估算旋转带来的表面线速度（推测接触的边际要用）
	var e := aabb.size
	return 0.5 * sqrt(e.x * e.x + e.y * e.y)

func refresh_com() -> void:
	## 缓存世界质心。求解器里每次算相对速度都会用到它，
	## 每帧重算 3000+ 次 Vector2 旋转在 GDScript 里是实打实的开销。
	_com_cache = position + local_com.rotated(rotation)

func com_world() -> Vector2:
	return _com_cache


func to_world(p: Vector2) -> Vector2:
	return position + p.rotated(rotation)


func to_local(p: Vector2) -> Vector2:
	return (p - position).rotated(-rotation)


func velocity_at(world_point: Vector2) -> Vector2:
	## v + w x r，2D 里叉乘退化为 (-w*r.y, w*r.x)
	var r := world_point - com_world()
	return linear_velocity + Vector2(-angular_velocity * r.y, angular_velocity * r.x)


func apply_impulse(impulse: Vector2, world_point: Vector2) -> void:
	if is_static or inv_mass <= 0.0:
		return
	linear_velocity += impulse * inv_mass
	angular_velocity += inv_inertia * (world_point - com_world()).cross(impulse)


## 冲量：**立即**改速度，不乘 dt。过质心，不产生力矩。
func apply_central_impulse(impulse: Vector2) -> void:
	if is_static or inv_mass <= 0.0:
		return
	linear_velocity += impulse * inv_mass


## 纯力矩冲量（角冲量）。
func apply_torque_impulse(t: float) -> void:
	if is_static or inv_inertia <= 0.0:
		return
	angular_velocity += inv_inertia * t


## 一次性"推一下"：等价于让力 force 作用 dt 秒。
## 只在确实想要瞬时推力时用它；**持续力请用 add_force**（见 accum_force 的说明）。
func apply_force_once(force: Vector2, world_point: Vector2, dt: float) -> void:
	apply_impulse(force * dt, world_point)


## 施加**过质心**的持久力（不产生力矩）。
##
## ⚠️ 施力会**唤醒**刚体（与 Box2D 一致）。少了这一步会出很隐蔽的 bug：
## 一个刚被加进来的物体速度还很小时就会被判为"慢"而睡着，
## 于是外力**再也施加不上**（实测 vx 恒为 0）。反过来，一直加力就等于不睡，
## 这是调用方的责任。
func add_force(force: Vector2) -> void:
	if force == Vector2.ZERO:
		return
	accum_force += force
	_wake_force()


## 在世界坐标点 world_point 处施加持久力 —— 该点不在质心时会同时产生力矩。
func add_force_at(force: Vector2, world_point: Vector2) -> void:
	if force == Vector2.ZERO:
		return
	accum_force += force
	accum_torque += (world_point - com_world()).cross(force)
	_wake_force()


## 施加持久力矩（纯转动）。
func add_torque(t: float) -> void:
	if t == 0.0:
		return
	accum_torque += t
	_wake_force()


func _wake_force() -> void:
	if not is_static:
		awake = true
		sleep_timer = 0.0


## 清空外力累加器。**每帧开头调一次**（见 accum_force 的说明）。
func clear_forces() -> void:
	accum_force = Vector2.ZERO
	accum_torque = 0.0


## 从静态转回动态（Shift 绘制是"先摆好、松手才变成刚体"）。
## 静态期间跳过了质量属性计算，所以这里必须做一次完整 rebuild。
func make_dynamic() -> void:
	is_static = false
	awake = true
	sleep_timer = 0.0
	rebuild(shapes)


func make_static() -> void:
	is_static = true
	awake = true
	mass = 0.0
	inertia = 0.0
	inv_mass = 0.0
	inv_inertia = 0.0
	local_com = Vector2.ZERO


## 用像素 Shape 重建质量属性与碰撞矩形。
## 组合律：并行的组合形状用平行轴定理逐块累加。
func rebuild(shape_list: Array, density_of: Callable = Callable(), max_rects: int = 64) -> void:
	shapes = shape_list
	rects.clear()
	# 静态体不需要质量属性（逆质量恒为 0，质心也不参与求解）。
	# 擦地形时每帧都会 rebuild，跳过逐像素扫描是实打实的收益。
	if is_static:
		for s0 in shape_list:
			var r0: GreedyRects.Result = GreedyRects.decompose(s0, max_rects)
			for rect0: Rect2 in r0.rects:
				rects.append(rect0)
		mass = 0.0
		inertia = 0.0
		inv_mass = 0.0
		inv_inertia = 0.0
		local_com = Vector2.ZERO
		refresh_com()
		update_aabb()
		return
	var m_total := 0.0
	var com := Vector2.ZERO
	var inertia_c := 0.0
	for s in shape_list:
		var p: MassProps.Props = MassProps.compute(s, density_of)
		m_total += p.mass
		com += p.com * p.mass
	var had_mass := m_total > 0.0
	if had_mass:
		com /= m_total
	for s2 in shape_list:
		var p2: MassProps.Props = MassProps.compute(s2, density_of)
		# 平行轴定理：把每块的惯性搬到自己质心之外
		inertia_c += p2.inertia + p2.mass * p2.com.distance_squared_to(com)
		var r: GreedyRects.Result = GreedyRects.decompose(s2, max_rects)
		for rect: Rect2 in r.rects:
			rects.append(rect)
	mass = m_total
	inertia = inertia_c
	local_com = com if had_mass else Vector2.ZERO
	if is_static:
		inv_mass = 0.0
		inv_inertia = 0.0
	else:
		inv_mass = 0.0 if mass <= 0.0 else 1.0 / mass
		inv_inertia = 0.0 if inertia <= 0.0 else 1.0 / inertia
	refresh_com()
	update_aabb()


func update_aabb() -> void:
	if rects.is_empty():
		aabb = Rect2(com_world(), Vector2.ZERO)
		swept_aabb = aabb
		return
	var r0: Rect2 = rects[0]
	var box := _rect_world_aabb(r0)
	for i in range(1, rects.size()):
		box = box.merge(_rect_world_aabb(rects[i]))
	aabb = box
	swept_aabb = box


## 本步内可能扫过的范围（线性位移 + 旋转扫过的半径）
func compute_swept_aabb(dt: float) -> void:
	var motion := linear_velocity.length() * dt + absf(angular_velocity) * bounding_radius() * dt
	swept_aabb = aabb.grow(motion)


func _rect_world_aabb(local_rect: Rect2) -> Rect2:
	var h := local_rect.size * 0.5
	var c := to_world(local_rect.position + h)
	# 旋转后的 AABB 半径
	var ex := absf(h.x * cos(rotation)) + absf(h.y * sin(rotation))
	var ey := absf(h.x * sin(rotation)) + absf(h.y * cos(rotation))
	return Rect2(c - Vector2(ex, ey), Vector2(ex, ey) * 2.0)


## 休眠判据：质心线速度 + **最快点**的表面速度（|ω| * 包围半径）。
##
## ⚠️ 这里曾经是"|v| <= 阈值 且 |ω| <= 另一个**绝对**角速度阈值(0.15 rad/s)"。
## 那个绝对阈值对**小碎块**过于苛刻：6x6 的碎块 ω=0.2 rad/s 时边缘线速度只有
## 0.6 px/s（肉眼完全静止），却超过 0.15 —— 它的 sleep_timer 于是每帧被清零，
## 而岛的休眠取**岛内最小值**，结果一整个大岛永远睡不着。
##
## 实测（tests/diag_sleep.gd）：300 碎块落定 16.7 秒后，335 个里 **322 个**
## 线速度已经在 0~2 px/s，却因为少数几个 ω=0.16~2.26 而全岛失眠；
## 稳定期帧时间 92.8 ms（本该是个位数）。
##
## 换成表面速度之后判据与尺寸无关，而且与 _compute_substeps 用的是**同一个量**。
func is_slow(lin_thresh: float, ang_thresh: float) -> bool:
	if linear_velocity.length_squared() > lin_thresh * lin_thresh:
		return false
	return absf(angular_velocity) * bounding_radius() <= ang_thresh

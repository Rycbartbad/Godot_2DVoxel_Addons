extends RefCounted
## OBB-OBB 碰撞：SAT 求最小穿透轴 + 参考面/入射面裁剪得到 2 点流形。
##
## 碰撞形状来自像素团的贪心矩形分解，所以全是 OBB。
## 2D SAT 每个盒子只有 2 个轴，最多 4 个分离轴；接触流形最多 2 个点。

const PBody := preload("res://addons/pixel_destruction/physics/pbody.gd")

class OBB:
	var center: Vector2
	var u: Vector2       # 单位轴 x
	var v: Vector2       # 单位轴 y
	var h: Vector2       # 半长

	func vertex(i: int) -> Vector2:
		match i:
			0: return center - u * h.x - v * h.y
			1: return center + u * h.x - v * h.y
			2: return center + u * h.x + v * h.y
			_: return center - u * h.x + v * h.y

	func edge_start(i: int) -> Vector2:
		return vertex(i)

	func edge_end(i: int) -> Vector2:
		return vertex((i + 1) % 4)

	func edge_normal(i: int) -> Vector2:
		match i:
			0: return -v
			1: return u
			2: return v
			_: return -u

	func project_radius(axis: Vector2) -> float:
		return absf(u.dot(axis)) * h.x + absf(v.dot(axis)) * h.y


static func obb_from_local_rect(body: PBody, r: Rect2) -> OBB:
	var o := OBB.new()
	var hl := r.size * 0.5
	o.center = body.to_world(r.position + hl)
	o.u = Vector2(cos(body.rotation), sin(body.rotation))
	o.v = Vector2(-o.u.y, o.u.x)
	o.h = hl
	return o


## SAT 结果的**类型化暂存**。
##
## 为什么要这么麻烦：GDScript 的容器访问一律返回 Variant，取值要装箱、
## 赋给有类型变量又要拆箱，而 Dictionary 本身还得分配一个 HashMap。
## 实测（tests/bench_variant.gd，2401 对 OBB）：
##   返回 Dictionary 2.877 us/次  →  写类型化字段 2.510 us/次，**1.15x（13% 的税）**。
## 而 sat_signed() 是**每对矩形**都要跑一次的，240 碎块场景每帧约 13700 次 ——
## 那 13% 就是每帧几毫秒。这正是"如果有 JIT/AOT 就能消掉"的那类开销，
## 解释器消不掉，只能靠手写类型化接口绕开。
##
## 由调用方持有（PWorld 里复用一个），所以不是全局可变状态，多线程也安全。
class Sat:
	var sep := 0.0
	var normal := Vector2.RIGHT
	var from_a := true


## 有符号分离量。sep > 0 = 分离（间隙），sep <= 0 = 穿透（深度 = -sep）。
## 这是推测接触（speculative contact）的基础：知道"还差多少才碰上"，
## 才能在这一步里把接近速度限制住，而不是等穿进去了再往外推。
## 结果写进 out，**不分配任何对象**。
static func sat_signed_into(a: OBB, b: OBB, out: Sat) -> void:
	var axes := [a.u, a.v, b.u, b.v]
	var best_sep := -INF
	var best_axis := Vector2.RIGHT
	var best_from_a := true
	var d_center := b.center - a.center
	for i in 4:
		var axis: Vector2 = axes[i]
		var ra := a.project_radius(axis)
		var rb := b.project_radius(axis)
		var d := d_center.dot(axis)
		var sep := absf(d) - (ra + rb)
		if sep > best_sep:
			best_sep = sep
			best_axis = axis if d >= 0.0 else -axis
			best_from_a = i < 2
	out.sep = best_sep
	out.normal = best_axis
	out.from_a = best_from_a


## Dictionary 版本，留给外部调用方与测试（热路径**不再**走它）
static func sat_signed(a: OBB, b: OBB) -> Dictionary:
	var out := Sat.new()
	sat_signed_into(a, b, out)
	return {"sep": out.sep, "normal": out.normal, "from_a": out.from_a}


## 推测接触（sep > 0）的接触点。
##
## ⚠️ 旧写法是两个支撑点的中点，**是错的**：support() 返回的是**角点**，
## 两盒切向跨度差很多时（小箱子 vs 半宽 2000 的地面）中点会落到距真实接触区
## 上千单位的地方 —— kn 因此巨大、normal_mass ≈ 0，**推测接触实际上是失效的**，
## 箱子落地全靠"穿透后走裁剪路径的 2 点接触"兜着。
##
## 正确做法：取 **A 朝 B 的支撑点**（它一定在 A 的表面上、朝 B 那一侧），
## 再把它的**切向坐标夹进 B 的切向范围**。这样接触点必然落在两者的共同区域内，
## 力臂是真实尺度，r_a / r_b 都不会离谱。
##
## ⚠️ 这个修复会**激活一个长期休眠的机制**，所以必须连同边际一起重新调参
## （见开发日志坑 34）—— 单独改它会让所有基准场景改变且箱子不再休眠。
static func speculative_point(a: OBB, b: OBB, n: Vector2) -> Vector2:
	var t := Vector2(-n.y, n.x)
	# 法向：两个支撑面的中点（落在两个表面之间）
	var pa := support(a, n)
	var pb := support(b, -n)
	var mid_n := (pa.dot(n) + pb.dot(n)) * 0.5
	# 切向：**两盒切向重叠区间的中心** ← 关键
	#
	# ⚠️ 不能用"两盒中心的中点"：小箱子 vs 半宽 2000 的地面时它会落在
	#    中间的空地上（实测偏出 50 单位）。也不能用支撑点/角点：
	#    面贴面时切向那一轴的重叠是任意的（由 dot >= 0 决定正负），
	#    接触点会落在**角点**上 → 虚假力矩 → 箱子被抽成陀螺。
	#    重叠区间的中心在面贴面时**正好是接触面的中心**，力臂为 0。
	var a_t := a.center.dot(t)
	var b_t := b.center.dot(t)
	var a_r := a.project_radius(t)
	var b_r := b.project_radius(t)
	var lo := maxf(a_t - a_r, b_t - b_r)
	var hi := minf(a_t + a_r, b_t + b_r)
	var mid_t := (a_t + b_t) * 0.5
	if lo <= hi:
		mid_t = (lo + hi) * 0.5
	return n * mid_n + t * mid_t


## 沿 dir 的最远点（支撑点）
static func support(o: OBB, dir: Vector2) -> Vector2:
	var p := o.center
	p += o.u * (o.h.x if o.u.dot(dir) >= 0.0 else -o.h.x)
	p += o.v * (o.h.y if o.v.dot(dir) >= 0.0 else -o.h.y)
	return p


## 返回 { hit, normal, depth, ref_is_a }
## normal 恒由 A 指向 B。
##
## 注意：collide() **不再调用它**（见那里的说明）—— sat_signed() 已经给出了同样的信息，
## 再跑一遍就是白白多一次 4 轴 SAT。留着它是给"只想要一个布尔命中判定"的调用方用的。
static func sat(a: OBB, b: OBB) -> Dictionary:
	var axes := [a.u, a.v, b.u, b.v]
	var best_depth := INF
	var best_axis := Vector2.RIGHT
	var best_from_a := true
	var d_center := b.center - a.center
	for i in 4:
		var axis: Vector2 = axes[i]
		var ra := a.project_radius(axis)
		var rb := b.project_radius(axis)
		var d := d_center.dot(axis)
		var overlap := ra + rb - absf(d)
		if overlap <= 0.0:
			return {"hit": false}
		if overlap < best_depth:
			best_depth = overlap
			best_axis = axis if d >= 0.0 else -axis
			best_from_a = i < 2
	return {
		"hit": true,
		"normal": best_axis,
		"depth": best_depth,
		"ref_is_a": best_from_a,
	}


## "没碰上"的**共享**返回值。
##
## ⚠️ 这不是省事，是热路径上最大的一笔浪费：
## 240 碎块的场景里每帧有约 **13000 对**矩形过了 AABB 粗筛，其中真正成接触的只有几百对。
## 旧写法给每一对"没碰上"都 new 一个 Dictionary + 一个 Array，只为说一句"没碰上" ——
## 一万三千次堆分配。调用方只读不写（_broadphase 只看 points / normal），所以共享是安全的。
static var _NO_CONTACT := {"normal": Vector2.RIGHT, "points": []}

## 生成接触流形。返回 {normal, points: Array[{position, depth, sep, feature}]}
## margin > 0 时会额外生成"推测接触"：两个盒子还没碰上、但这一步内可能碰上的也返回。
## sat 是调用方复用的暂存（PWorld 持有）；传 null 时临时建一个（外部调用方便）。
static func collide(a: OBB, b: OBB, margin: float = 0.0, sat: Sat = null) -> Dictionary:
	var s: Sat = sat if sat != null else Sat.new()
	sat_signed_into(a, b, s)
	var sep := s.sep
	if sep > margin:
		return _NO_CONTACT
	var normal := s.normal
	if sep > 0.0:
		# 分离但在边际内：给一个推测接触点，约束会把接近速度限制到"刚好接触"
		return {"normal": normal, "points": [
			{"position": speculative_point(a, b, normal), "depth": 0.0, "sep": sep, "feature": -1}]}
	# 已穿透：走参考面/入射面裁剪。
	#
	# ⚠️ 这里**不再**第二次调用 sat() —— 它的整个 4 轴循环就是 sat_signed() 刚刚跑过的那一遍。
	# 两者对"最小穿透轴"的选择规则完全一致（sat 用 overlap < best_depth、
	# sat_signed 用 sep > best_sep，而 sep = -overlap，都是从 ±INF 起的严格比较），
	# 所以复用是**逐位等价**的（由 tests/dump_state.gd 比对确认）。
	# 另外 sep <= 0 时不可能存在分离轴，sat() 必然返回 hit = true，那个分支本来就到不了。
	#
	# ⚠️ 边界：sep 恰好为 0（面贴面）时，老代码里的 sat() 会因为某条轴的
	# overlap <= 0 而提前返回 hit = false，于是**根本不生成接触点**。
	# 这个行为必须原样保留 —— 少了它，"箱阵面贴面摆放"的接触集会多出一批，
	# 物理结果随之改变（dump_state 立刻就能看出来）。
	# 注意 -0.0 >= 0.0 为真，与旧的 overlap <= 0.0 判定一致。
	if sep >= 0.0:
		return _NO_CONTACT
	var from_a := s.from_a
	var ref: OBB = a if from_a else b
	var inc: OBB = b if from_a else a
	var ref_normal := normal if from_a else -normal

	# 参考面 = 外法线与 ref_normal 最同向的边
	var ref_edge := 0
	var best_dot := -INF
	for i in 4:
		var d := ref.edge_normal(i).dot(ref_normal)
		if d > best_dot:
			best_dot = d
			ref_edge = i
	# 入射面 = 外法线与 ref_normal 最反向的边
	var inc_edge := 0
	var worst_dot := INF
	for i in 4:
		var d2 := inc.edge_normal(i).dot(ref_normal)
		if d2 < worst_dot:
			worst_dot = d2
			inc_edge = i

	var rp1 := ref.edge_start(ref_edge)
	var rp2 := ref.edge_end(ref_edge)
	var ip1 := inc.edge_start(inc_edge)
	var ip2 := inc.edge_end(inc_edge)

	# 用参考面两条侧平面裁剪入射面
	var tangent := (rp2 - rp1).normalized()
	var seg := _clip_segment(ip1, ip2, -tangent, -tangent.dot(rp1))
	if seg.is_empty():
		return {"normal": normal, "points": []}
	seg = _clip_segment(seg[0], seg[1], tangent, tangent.dot(rp2))
	if seg.is_empty():
		return {"normal": normal, "points": []}

	# 特征 id：参考边 + 入射边 + 裁剪序号。
	# 只要这几项不变，就说明是"同一个接触特征"，
	# warm start 才可以安全地沿用上一帧的累积冲量。
	# 参考边一旦翻转（例如 SAT 换了分离轴），id 随之改变，
	# 累积冲量自动作废，而不是被错误地搬到别的接触点上。
	var base := ref_edge * 16 + inc_edge * 4
	var out: Array = []
	for i in seg.size():
		var p: Vector2 = seg[i]
		var separation := (p - rp1).dot(ref_normal)
		if separation <= 0.0:
			out.append({"position": p, "depth": -separation, "sep": separation, "feature": base + i})
	return {"normal": normal, "points": out}


## 保留 dot(n, p) <= offset 的部分
static func _clip_segment(p1: Vector2, p2: Vector2, n: Vector2, offset: float) -> Array:
	var d1 := n.dot(p1) - offset
	var d2 := n.dot(p2) - offset
	if d1 <= 0.0 and d2 <= 0.0:
		return [p1, p2]
	if d1 > 0.0 and d2 > 0.0:
		return []
	if d1 > 0.0:
		var t := d1 / (d1 - d2)
		return [p1.lerp(p2, t), p2]
	var t2 := d2 / (d2 - d1)
	return [p1, p1.lerp(p2, t2)]

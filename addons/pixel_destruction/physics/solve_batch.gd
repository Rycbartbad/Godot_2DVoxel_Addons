extends RefCounted
## SoA（结构数组）求解器批次。
##
## 存在的唯一理由：**对象属性读写在多线程并发下会剧烈膨胀**。
## 实测（tests/bench_datalayout.gd，同一轮内对照）：
##   对象属性 (AoS)：16 线程时单元耗时膨胀 **88~93 倍**，并行后只有自己串行的 0.18x
##   PackedFloat64Array：膨胀 **5 倍**（与纯算术同级），并行后是自己串行的 **3.3x**
## 也就是说：**只要内层循环不碰对象属性，4 线程的天花板就不存在了。**
##
## 设计原则：
##   · **对象仍然是权威数据结构** —— Manifold / Point / PBody 照旧由 pworld 构建，
##     拓扑、warm key、feature id、位置等都在对象上。
##   · 只有 **10 次迭代的内层循环** 改成纯 packed 数组：gather 一次 -> 迭代 -> scatter 一次。
##   · 运算顺序与旧实现逐字对应（Vector2 的分量式展开），所以结果**逐位一致**，
##     由 tests/dump_state.gd 卡住。
##
## 约定：body slot 直接用 bodies 数组下标，省掉一层映射；
## static / 睡眠体的 b_wr = 0（不可写），逆质量逆惯量也记 0。

const PBody := preload("res://addons/pixel_destruction/physics/pbody.gd")
const Solver := preload("res://addons/pixel_destruction/physics/solver.gd")

# ---- 可调参数（由 PWorld.solver 同步过来）----
var iterations := 10
var baumgarte := 0.15
var penetration_slop := 0.5
var max_depenetration_speed := 100.0
var restitution_velocity_threshold := 40.0
var global_restitution := 0.0
var global_friction := 0.5
var use_block_solver := true
## 临时调试
var debug := false
var no_warm := false

# ---- 物体（下标 = bodies 下标）----
##
## ⚠️ **数组宽度必须逐字段对齐对象上的类型**，否则物理会变：
##   Godot 的 Vector2 是 real_t = **float32**，而 GDScript 的 float 是 float64。
##   所以凡是对象上属于 Vector2 的量（速度、r_a/r_b、法向/切向）必须用
##   PackedFloat32Array —— 这样"每次写回都舍入到 float32"的行为与 Vector2 一致。
##   而对象上是裸 float 的量（角速度、逆质量、有效质量、冲量、mu、k12）用 Float64。
##   第一版我全用了 Float64，结果整个内层变成双精度：单箱落地会翻倒、
##   三层堆叠从精确的 100.000 漂到 102.55、还有箱子直接穿过地板。
var nb := 0
var b_vx := PackedFloat32Array()
var b_vy := PackedFloat32Array()
var b_vw := PackedFloat64Array()
var b_px := PackedFloat32Array()
var b_py := PackedFloat32Array()
var b_pw := PackedFloat64Array()
var b_im := PackedFloat64Array()
var b_ii := PackedFloat64Array()
var b_wr := PackedByteArray()
## id -> bodies 下标。**不能假设 id == 下标 + 1** —— 一旦 remove_body，
## _next_id 不回收，id 与下标就永久错开了。
var _idx_of := {}

# ---- 流形 ----
var nm := 0
var m_nx := PackedFloat32Array()
var m_ny := PackedFloat32Array()
var m_tx := PackedFloat32Array()
var m_ty := PackedFloat32Array()
var m_mu := PackedFloat64Array()
var m_k12 := PackedFloat64Array()
var m_p0 := PackedInt32Array()
var m_p1 := PackedInt32Array()
var m_two := PackedByteArray()
var m_key := PackedInt64Array()

# ---- 接触点 ----
var np := 0
var p_ba := PackedInt32Array()
var p_bb := PackedInt32Array()
var p_feat := PackedInt32Array()
var p_rax := PackedFloat32Array()
var p_ray := PackedFloat32Array()
var p_rbx := PackedFloat32Array()
var p_rby := PackedFloat32Array()
var p_kn := PackedFloat64Array()
var p_nm := PackedFloat64Array()
var p_tm := PackedFloat64Array()
var p_vb := PackedFloat64Array()
var p_pb := PackedFloat64Array()
var p_ni := PackedFloat64Array()
var p_ti := PackedFloat64Array()
var p_pni := PackedFloat64Array()


func sync_params(s: Solver) -> void:
	iterations = s.iterations
	baumgarte = s.baumgarte
	penetration_slop = s.penetration_slop
	max_depenetration_speed = s.max_depenetration_speed
	restitution_velocity_threshold = s.restitution_velocity_threshold
	global_restitution = s.global_restitution
	global_friction = s.global_friction
	use_block_solver = s.use_block_solver


## 把物体状态 gather 进 packed 数组
func gather_bodies(bodies: Array) -> void:
	var n := bodies.size()
	nb = n
	b_vx.resize(n); b_vy.resize(n); b_vw.resize(n)
	b_px.resize(n); b_py.resize(n); b_pw.resize(n)
	b_im.resize(n); b_ii.resize(n)
	b_wr.resize(n)
	_idx_of.clear()
	for i in n:
		var b: PBody = bodies[i]
		_idx_of[b.id] = i
		# 可写判定与旧实现一致：清醒且非静态
		var wr := b.awake and not b.is_static
		b_wr[i] = 1 if wr else 0
		b_vx[i] = b.linear_velocity.x
		b_vy[i] = b.linear_velocity.y
		b_vw[i] = b.angular_velocity
		b_px[i] = b.pseudo_linear_velocity.x
		b_py[i] = b.pseudo_linear_velocity.y
		b_pw[i] = b.pseudo_angular_velocity
		if wr:
			b_im[i] = b.inv_mass
			b_ii[i] = b.inv_inertia
		else:
			b_im[i] = 0.0
			b_ii[i] = 0.0


## 把求解结果 scatter 回物体
func scatter_bodies(bodies: Array) -> void:
	for i in nb:
		var b: PBody = bodies[i]
		if b_wr[i] == 0:
			continue
		b.linear_velocity = Vector2(b_vx[i], b_vy[i])
		b.angular_velocity = b_vw[i]
		b.pseudo_linear_velocity = Vector2(b_px[i], b_py[i])
		b.pseudo_angular_velocity = b_pw[i]


## perm 是流形下标的排列（按岛分组，岛内保持原顺序）。
## 做的是旧 solve.prepare() 的全部工作，只是结果写进 packed 数组。
func build(manifolds: Array, perm: PackedInt32Array, dt: float, warm: Dictionary, bodies: Array) -> void:
	var n := manifolds.size()
	nm = n
	if n == 0:
		np = 0
		return
	m_nx.resize(n); m_ny.resize(n); m_tx.resize(n); m_ty.resize(n)
	m_mu.resize(n); m_k12.resize(n)
	m_p0.resize(n); m_p1.resize(n); m_two.resize(n); m_key.resize(n)
	var total_points := 0
	for mi in n:
		total_points += (manifolds[perm[mi]].points as Array).size()
	np = total_points
	p_ba.resize(total_points); p_bb.resize(total_points); p_feat.resize(total_points)
	p_rax.resize(total_points); p_ray.resize(total_points)
	p_rbx.resize(total_points); p_rby.resize(total_points)
	p_kn.resize(total_points); p_nm.resize(total_points); p_tm.resize(total_points)
	p_vb.resize(total_points); p_pb.resize(total_points)
	p_ni.resize(total_points); p_ti.resize(total_points); p_pni.resize(total_points)

	var pi := 0
	for mi2 in n:
		var m: Solver.Manifold = manifolds[perm[mi2]]
		var a: PBody = m.a
		var b: PBody = m.b
		var nx: float = m.normal.x
		var ny: float = m.normal.y
		var tx := -ny
		var ty := nx
		var mu := maxf(m.friction, global_friction)
		m_nx[mi2] = nx
		m_ny[mi2] = ny
		m_tx[mi2] = tx
		m_ty[mi2] = ty
		m_mu[mi2] = mu
		m_key[mi2] = m.key
		# ⚠️ 不能用 id-1 当 slot：remove_body 之后 id 与下标就错开了
		var ia: int = _idx_of.get(a.id, -1)
		var ib: int = _idx_of.get(b.id, -1)
		var pts: Array = m.points
		var cnt := pts.size()
		m_two[mi2] = 1 if cnt == 2 else 0
		m_p0[mi2] = pi
		m_p1[mi2] = pi + 1
		var e := maxf(m.restitution, global_restitution)
		var warm_m: Dictionary = warm.get(m.key, {})
		var com_a := a.com_world()
		var com_b := b.com_world()
		var wa: bool = a.awake and not a.is_static
		var wb: bool = b.awake and not b.is_static
		var iaa := a.inv_inertia if wa else 0.0
		var ibb := b.inv_inertia if wb else 0.0
		var maa := a.inv_mass if wa else 0.0
		var mbb := b.inv_mass if wb else 0.0
		var k12 := 0.0
		for k in cnt:
			var p: Solver.Point = pts[k]
			var rax: float = p.position.x - com_a.x
			var ray: float = p.position.y - com_a.y
			var rbx: float = p.position.x - com_b.x
			var rby: float = p.position.y - com_b.y
			p_ba[pi] = ia
			p_bb[pi] = ib
			p_rax[pi] = rax
			p_ray[pi] = ray
			p_rbx[pi] = rbx
			p_rby[pi] = rby
			var rna := rax * ny - ray * nx
			var rnb := rbx * ny - rby * nx
			var kn := maa + mbb + iaa * rna * rna + ibb * rnb * rnb
			p_kn[pi] = kn
			p_nm[pi] = 0.0 if kn <= 0.0 else 1.0 / kn
			var rta := rax * ty - ray * tx
			var rtb := rbx * ty - rby * tx
			var kt := maa + mbb + iaa * rta * rta + ibb * rtb * rtb
			p_tm[pi] = 0.0 if kt <= 0.0 else 1.0 / kt
			# 恢复系数与推测接触（与旧 prepare 逐字一致）。
			#
			# ⚠️ 这里**必须从 packed 数组读速度，不能读 PBody**：
			# 前一个接触点的 warm-start 冲量是通过 _apply_point 写进数组的，
			# 而 PBody 上的速度要到整个 solve 结束才 scatter 回去。
			# 旧写法读 PBody，于是"点 1 的 velocity_bias"看不见"点 0 已经施加的 warm 冲量"，
			# 两点对称性被打破 —— 实测对象路径两点的累积冲量完全相同，
			# 而 SoA 会分化，进而长出虚假的切向冲量、堆叠漂移、箱子翻倒。
			# （这也解释了为什么"关掉 warm start 就完全一致"：那时 _apply_point 是空操作。）
			var vbx := b_vx[ib] + (-b_vw[ib] * rby)
			var vby := b_vy[ib] + (b_vw[ib] * rbx)
			var vax := b_vx[ia] + (-b_vw[ia] * ray)
			var vay := b_vy[ia] + (b_vw[ia] * rax)
			var vn := (vbx - vax) * nx + (vby - vay) * ny
			var bias := 0.0
			if vn < -restitution_velocity_threshold:
				bias = -e * vn
			var sep: float = p.separation
			if sep > 0.0:
				bias = maxf(bias, -sep / dt)
			p_vb[pi] = bias
			var pen := maxf(0.0, -sep - penetration_slop) * baumgarte / dt
			p_pb[pi] = minf(pen, max_depenetration_speed)
			p_pni[pi] = 0.0
			var ni := 0.0
			var ti := 0.0
			if not no_warm:
				var w: Variant = warm_m.get(p.feature_id)
				if w != null:
					ni = w.x
					ti = w.y
			p_ni[pi] = ni
			p_ti[pi] = ti
			p_feat[pi] = p.feature_id
			if debug and pi == 0:
				print("  [build] a=%s b=%s | vn=%9.4f bias=%9.4f nm=%9.6f kn=%9.6f sep=%9.6f | va=(%.4f,%.4f) vb=(%.4f,%.4f)" % [
					a.id, b.id, vn, bias, p_nm[pi], kn, sep,
					a.linear_velocity.x, a.linear_velocity.y,
					b.linear_velocity.x, b.linear_velocity.y])
			# warm start 立刻施加（与旧 prepare 的 _apply 等价）
			_apply_point(pi, nx * ni, ny * ni)
			_apply_point(pi, tx * ti, ty * ti)
			pi += 1
		# k12：两个接触点的耦合项（与旧实现同序）
		if cnt == 2:
			var q0 := m_p0[mi2]
			var q1 := m_p1[mi2]
			var rna0 := p_rax[q0] * ny - p_ray[q0] * nx
			var rnb0 := p_rbx[q0] * ny - p_rby[q0] * nx
			var rna1 := p_rax[q1] * ny - p_ray[q1] * nx
			var rnb1 := p_rbx[q1] * ny - p_rby[q1] * nx
			k12 = maa + mbb + iaa * rna0 * rna1 + ibb * rnb0 * rnb1
		m_k12[mi2] = k12


## 复刻旧 _apply：把冲量施加到某个体现在**packed 数组**上的接触点
func _apply_point(pi: int, ix: float, iy: float) -> void:
	if ix == 0.0 and iy == 0.0:
		return
	var ba := p_ba[pi]
	var bb := p_bb[pi]
	if b_wr[ba] == 1:
		var ma := b_im[ba]
		b_vx[ba] -= ix * ma
		b_vy[ba] -= iy * ma
		b_vw[ba] -= b_ii[ba] * (p_rax[pi] * iy - p_ray[pi] * ix)
	if b_wr[bb] == 1:
		var mb := b_im[bb]
		b_vx[bb] += ix * mb
		b_vy[bb] += iy * mb
		b_vw[bb] += b_ii[bb] * (p_rbx[pi] * iy - p_rby[pi] * ix)


func solve_all(dt: float) -> void:
	_solve_range(0, nm, dt)


## 并行入口：一个岛对应一段连续区间，段内顺序与串行完全一致
func solve_range(lo: int, hi: int, dt: float) -> void:
	_solve_range(lo, hi, dt)


func _solve_range(lo: int, hi: int, dt: float) -> void:
	if debug and lo == 0 and hi > 0:
		print("  [solve前] ni=%.4f | 速度: ", p_ni[0])
		for i in nb:
			if b_wr[i] == 1:
				print("      body %d v=(%.4f, %.4f) w=%.6f" % [i, b_vx[i], b_vy[i], b_vw[i]])
	for it in iterations:
		for mi in range(lo, hi):
			var q0 := m_p0[mi]
			var two := use_block_solver and m_two[mi] == 1
			if two:
				_block(mi, q0, m_p1[mi])
			var cnt := 2 if m_two[mi] == 1 else 1
			var k := 0
			while k < cnt:
				var pi := q0 if k == 0 else m_p1[mi]
				var ba := p_ba[pi]
				var bb := p_bb[pi]
				var nx := m_nx[mi]
				var ny := m_ny[mi]
				var wa := b_wr[ba] == 1
				var wb := b_wr[bb] == 1
				var ma := b_im[ba]
				var mb := b_im[bb]
				var ia := b_ii[ba]
				var ib := b_ii[bb]
				if not two:
					var vbx2 := b_vx[bb] + (-b_vw[bb] * p_rby[pi])
					var vby2 := b_vy[bb] + (b_vw[bb] * p_rbx[pi])
					var vax2 := b_vx[ba] + (-b_vw[ba] * p_ray[pi])
					var vay2 := b_vy[ba] + (b_vw[ba] * p_rax[pi])
					var vn := (vbx2 - vax2) * nx + (vby2 - vay2) * ny
					var dl := p_nm[pi] * (p_vb[pi] - vn)
					var newn := maxf(p_ni[pi] + dl, 0.0)
					dl = newn - p_ni[pi]
					p_ni[pi] = newn
					var ix := nx * dl
					var iy := ny * dl
					if ix != 0.0 or iy != 0.0:
						if wa:
							b_vx[ba] -= ix * ma
							b_vy[ba] -= iy * ma
							b_vw[ba] -= ia * (p_rax[pi] * iy - p_ray[pi] * ix)
						if wb:
							b_vx[bb] += ix * mb
							b_vy[bb] += iy * mb
							b_vw[bb] += ib * (p_rbx[pi] * iy - p_rby[pi] * ix)
				# 伪速度通道
				if p_pb[pi] > 0.0 and p_nm[pi] > 0.0:
					var pvbx := b_px[bb] + (-b_pw[bb] * p_rby[pi])
					var pvby := b_py[bb] + (b_pw[bb] * p_rbx[pi])
					var pvax := b_px[ba] + (-b_pw[ba] * p_ray[pi])
					var pvay := b_py[ba] + (b_pw[ba] * p_rax[pi])
					var pvn := (pvbx - pvax) * nx + (pvby - pvay) * ny
					var pdl := p_nm[pi] * (p_pb[pi] - pvn)
					var pnew := maxf(p_pni[pi] + pdl, 0.0)
					pdl = pnew - p_pni[pi]
					p_pni[pi] = pnew
					var pix := nx * pdl
					var piy := ny * pdl
					if pix != 0.0 or piy != 0.0:
						if wa:
							b_px[ba] -= pix * ma
							b_py[ba] -= piy * ma
							b_pw[ba] -= ia * (p_rax[pi] * piy - p_ray[pi] * pix)
						if wb:
							b_px[bb] += pix * mb
							b_py[bb] += piy * mb
							b_pw[bb] += ib * (p_rbx[pi] * piy - p_rby[pi] * pix)
				# 切向摩擦
				var tx := m_tx[mi]
				var ty := m_ty[mi]
				var vbx3 := b_vx[bb] + (-b_vw[bb] * p_rby[pi])
				var vby3 := b_vy[bb] + (b_vw[bb] * p_rbx[pi])
				var vax3 := b_vx[ba] + (-b_vw[ba] * p_ray[pi])
				var vay3 := b_vy[ba] + (b_vw[ba] * p_rax[pi])
				var dt_imp := -p_tm[pi] * ((vbx3 - vax3) * tx + (vby3 - vay3) * ty)
				var max_f := m_mu[mi] * p_ni[pi]
				var newt := clampf(p_ti[pi] + dt_imp, -max_f, max_f)
				dt_imp = newt - p_ti[pi]
				p_ti[pi] = newt
				var jx := tx * dt_imp
				var jy := ty * dt_imp
				if jx != 0.0 or jy != 0.0:
					if wa:
						b_vx[ba] -= jx * ma
						b_vy[ba] -= jy * ma
						b_vw[ba] -= ia * (p_rax[pi] * jy - p_ray[pi] * jx)
					if wb:
						b_vx[bb] += jx * mb
						b_vy[bb] += jy * mb
						b_vw[bb] += ib * (p_rbx[pi] * jy - p_rby[pi] * jx)
				k += 1


## 2 点法向块求解器（与旧 _solve_block_normal 同序）
func _block(mi: int, q0: int, q1: int) -> void:
	var k11 := p_kn[q0]
	var k22 := p_kn[q1]
	var k12 := m_k12[mi]
	var nx := m_nx[mi]
	var ny := m_ny[mi]
	var ba := p_ba[q0]
	var bb := p_bb[q0]
	var vb1x := b_vx[bb] + (-b_vw[bb] * p_rby[q0])
	var vb1y := b_vy[bb] + (b_vw[bb] * p_rbx[q0])
	var va1x := b_vx[ba] + (-b_vw[ba] * p_ray[q0])
	var va1y := b_vy[ba] + (b_vw[ba] * p_rax[q0])
	var ba2 := p_ba[q1]
	var bb2 := p_bb[q1]
	var vb2x := b_vx[bb2] + (-b_vw[bb2] * p_rby[q1])
	var vb2y := b_vy[bb2] + (b_vw[bb2] * p_rbx[q1])
	var va2x := b_vx[ba2] + (-b_vw[ba2] * p_ray[q1])
	var va2y := b_vy[ba2] + (b_vw[ba2] * p_rax[q1])
	var vn1 := (vb1x - va1x) * nx + (vb1y - va1y) * ny
	var vn2 := (vb2x - va2x) * nx + (vb2y - va2y) * ny
	var rhs1 := p_vb[q0] - vn1
	var rhs2 := p_vb[q1] - vn2
	var x1 := p_ni[q0]
	var x2 := p_ni[q1]
	var dx1 := 0.0
	var dx2 := 0.0
	var solved := false
	var det := k11 * k22 - k12 * k12
	if absf(det) > 1e-12:
		dx1 = (k22 * rhs1 - k12 * rhs2) / det
		dx2 = (k11 * rhs2 - k12 * rhs1) / det
		if x1 + dx1 >= 0.0 and x2 + dx2 >= 0.0:
			solved = true
	if not solved and k22 > 1e-12:
		var d2 := rhs2 / k22
		if x2 + d2 >= 0.0 and k12 * (x2 + d2) - rhs1 >= -1e-9:
			dx1 = -x1
			dx2 = d2
			solved = true
	if not solved and k11 > 1e-12:
		var d1 := rhs1 / k11
		if x1 + d1 >= 0.0 and k12 * (x1 + d1) - rhs2 >= -1e-9:
			dx1 = d1
			dx2 = -x2
			solved = true
	if not solved:
		if rhs1 <= 0.0 and rhs2 <= 0.0:
			dx1 = -x1
			dx2 = -x2
		else:
			return
	p_ni[q0] = x1 + dx1
	p_ni[q1] = x2 + dx2
	_apply_point(q0, nx * dx1, ny * dx1)
	_apply_point(q1, nx * dx2, ny * dx2)


## 把累积冲量写回 warm 缓存（与旧 store_warm 等价）
func store_warm(warm: Dictionary, manifolds: Array, perm: PackedInt32Array) -> void:
	for mi in nm:
		var m: Solver.Manifold = manifolds[perm[mi]]
		var q0 := m_p0[mi]
		var cnt := 2 if m_two[mi] == 1 else 1
		var d := {}
		var k := 0
		while k < cnt:
			var pi := q0 if k == 0 else m_p1[mi]
			d[p_feat[pi]] = Vector2(p_ni[pi], p_ti[pi])
			k += 1
		if d.is_empty():
			warm.erase(m_key[mi])
		else:
			warm[m_key[mi]] = d

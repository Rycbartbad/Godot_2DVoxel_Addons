extends SceneTree
## 第 4 层验证：PBF 粒子流体（src/fluid/fluid_pbf.gd + 原生 PixelFluid）。
##
## 判据分两组：
##   · **语义**（参照实现自己就对）：守恒 / 收敛 / 取向 / 有界 / 连续掉血；
##   · **等价**（原生 == 参照）：同数据跑 N 步，pos/vel **逐位相同**。
##
## ⚠️ 第二组是本文件存在的**主要**理由。这个仓库对原生内核的既定判据就是
##    "逐位相同"（见 tests/validation_raster_native.gd / validation_greedy_native.gd），
##    流体没有理由破例 —— 它没有 Rapier 那种"两边都算不准"的借口。
##    扩展没加载时这一组会**明确报 SKIP**，不会静默变成通过。
const FluidPBF := preload("res://src/fluid/fluid_pbf.gd")

var _pass := 0
var _fail := 0
var _skip := 0

func _c(n: String, ok: bool, d: String = "") -> void:
	if ok:
		_pass += 1
		print("  PASS  ", n, "  ", d)
	else:
		_fail += 1
		print("  FAIL  ", n, "  ", d)

func _s(n: String, why: String) -> void:
	_skip += 1
	print("  SKIP  ", n, "  ", why)


## 造一个已初始化、已排好粒子的场。
func _make(count: int = 130) -> Object:
	var f = FluidPBF.new()
	f.resize_grid(17, 18)
	f.max_particles = 130
	f.init_particles(count)
	return f


func _all_inside(f) -> bool:
	for i in f.particle_count():
		var x: float = f.pos[i * 2]
		var y: float = f.pos[i * 2 + 1]
		if x < f._min_x - 1e-9 or x > f._max_x + 1e-9:
			return false
		if y < f._min_y - 1e-9 or y > f._max_y + 1e-9:
			return false
	return true


## 粒子有没有落在**固体格**里。参照实现没有这个概念（它的容器是矩形，
## 域钳位和边界重合），所以这一组是新增能力自己的闸门。
func _count_out_of_mask(f) -> int:
	var h: float = f.spacing
	var bad := 0
	for i in f.particle_count():
		var cx := clampi(int(f.pos[i * 2] / h), 0, f.num_x - 1)
		var cy := clampi(int(f.pos[i * 2 + 1] / h), 0, f.num_y - 1)
		if f.solid_mask[cx * f.num_y + cy] == 0:
			bad += 1
	return bad


func _finite(f) -> bool:
	for v in f.pos:
		if is_nan(v) or is_inf(v):
			return false
	for v in f.vel:
		if is_nan(v) or is_inf(v):
			return false
	return true


func _max_speed(f) -> float:
	var m := 0.0
	for i in f.particle_count():
		var s: float = sqrt(f.vel[i * 2] * f.vel[i * 2] + f.vel[i * 2 + 1] * f.vel[i * 2 + 1])
		m = maxf(m, s)
	return m


func _com(f) -> Vector2:
	var c := Vector2.ZERO
	var n: int = f.particle_count()
	if n == 0:
		return c
	for i in n:
		c += Vector2(f.pos[i * 2], f.pos[i * 2 + 1])
	return c / float(n)


func _ink_cells(f) -> int:
	var n := 0
	for v in f.ink:
		if v != 0:
			n += 1
	return n


func _initialize() -> void:
	print("=== 初始化 ===")
	var f = _make(130)
	_c("粒子数 = 请求数", f.particle_count() == 130, "%d" % f.particle_count())
	_c("可通行格 = 内部 15x16", _count_nonzero(f.solid_mask) == 240,
		"%d" % _count_nonzero(f.solid_mask))
	_c("初始全在域内", _all_inside(f))
	_c("初始速度全 0", _max_speed(f) == 0.0)
	# ⚠️ 参照实现会把排不满的粒子堆在左上角，那会把首帧的 restDensity 带偏。
	#    这里刻意不堆 —— 这条断言钉住"少几个粒子也不许堆"。
	var f2 = _make(1000)
	_c("超量请求不会堆在角落", _all_inside(f2), "%d 粒子" % f2.particle_count())

	print("=== 静止收敛（300 步，重力向下）===")
	f.fill_ratio = -1.0
	for i in 300:
		f.step(0.0, 9.8)
	# ⚠️ 走原生时 pos/vel/rest_density 的权威副本在原生那边 —— 下面每一条断言
	#    都要先拉回来，否则读的是"刚 load 进去的初始值"，而它**看起来一切正常**
	#    （还在域内、没有 NaN），只是永远不动。
	f.sync_from_native()
	_c("不发散（无 NaN/Inf）", _finite(f))
	_c("始终在域内", _all_inside(f))
	_c("收敛（最大速度 < 1.0）", _max_speed(f) < 1.0, "%.4f" % _max_speed(f))
	var com := _com(f)
	_c("沉到底部（质心 y > 域中线）", com.y > float(f.num_y) * f.spacing * 0.5,
		"y=%.4f 中线=%.4f" % [com.y, float(f.num_y) * f.spacing * 0.5])
	_c("静止密度已定出", f.rest_density > 0.0, "%.6f" % f.rest_density)
	_c("ink 覆盖与粒子数同量级", _ink_cells(f) >= 60 and _ink_cells(f) <= 130,
		"%d / 130 粒子" % _ink_cells(f))
	_c("粒子数不变（未开液量控制）", f.particle_count() == 130, "%d" % f.particle_count())

	print("=== 旋转取向（重力转 90 度）===")
	var before := _com(f)
	for i in 300:
		f.step(9.8, 0.0)
	f.sync_from_native()
	var after := _com(f)
	_c("液体跟着新重力走（质心 x 明显右移）", after.x - before.x > 0.1,
		"dx=%.4f（%.4f -> %.4f）" % [after.x - before.x, before.x, after.x])
	_c("旋转后仍然有界", _finite(f) and _all_inside(f))

	print("=== 连续掉血（不是一下删完）===")
	var g = _make(130)
	g.fill_rate = 2
	for i in 120:
		g.step(0.0, 9.8)
	var n0: int = g.particle_count()
	g.set_fill_ratio(0.5)
	_c("set_fill_ratio 只设目标，不动粒子数", g.particle_count() == n0,
		"%d -> %d" % [n0, g.particle_count()])
	# 每步最多掉 fill_rate 个 —— 这条是"连续过程"的**定义**，不是估计
	# ⚠️ 判据按**契约**写，不写死数字。
	#    契约是 max(fill_rate, ceil(误差 * fill_gain))：小差额由下限兜住（平滑），
	#    大差额由比例项加速（收敛）。第一版这里写死 <= 2，改了契约之后立刻误报 ——
	#    而它误报的样子很像"连续掉血被破坏了"。
	var worst := 0
	var over := 0
	var prev := n0
	var steps_to_converge := -1
	for i in 400:
		# ⚠️ 显式标 int：g 是 Object，particle_count() 返回 Variant，:= 推不出来
		var err: int = g.particle_count() - 65
		var limit := maxi(2, int(ceil(float(absi(err)) * 0.06)))
		g.step(0.0, 9.8)
		var d: int = prev - g.particle_count()
		worst = maxi(worst, d)
		if d > limit:
			over += 1
		prev = g.particle_count()
		if g.particle_count() <= 65 and steps_to_converge < 0:
			steps_to_converge = i + 1
	_c("每步掉的不超过 max(fill_rate, 误差*gain)", over == 0,
		"最大单步 %d，越界 %d 次" % [worst, over])
	_c("最终收敛到目标（65 个）", g.particle_count() == 65, "%d" % g.particle_count())
	_c("收敛发生在多步之后（不是一步到位）", steps_to_converge > 10,
		"%d 步" % steps_to_converge)
	_c("掉血过程中始终在域内", _all_inside(g))
	g.sync_from_native()
	_c("掉血不重算静止密度基准", absf(g.rest_density - f.rest_density) < 1e-9,
		"%.9f vs %.9f" % [g.rest_density, f.rest_density])

	print("=== 剧烈翻转（有界性）===")
	var h = _make(130)
	var dirs := [Vector2(0, 1), Vector2(1, 0), Vector2(0, -1), Vector2(-1, 0), Vector2(0.7, 0.7)]
	for i in 200:
		var d: Vector2 = dirs[i % dirs.size()]
		h.step(d.x * 9.8, d.y * 9.8)
	_c("每 5 步换一次重力方向也不发散", _finite(h))
	_c("剧烈翻转后仍在域内", _all_inside(h))

	print("=== 异形容器（掩码不是矩形）===")
	# 圆形掩码 —— 外接矩形里有一半是固体。参照实现从没测过这种容器。
	var circ = FluidPBF.new()
	circ.resize_grid(24, 24)
	for x in 24:
		for y in 24:
			var dx := (float(x) + 0.5) - 12.0
			var dy := (float(y) + 0.5) - 12.0
			circ.solid_mask[x * 24 + y] = 1 if dx * dx + dy * dy <= 90.25 else 0
	var passable := _count_nonzero(circ.solid_mask)
	_c("圆形掩码的可通行格远少于外接矩形", passable > 200 and passable < 500,
		"%d / 576" % passable)
	var made: int = circ.init_particles(-1)
	# ⚠️ 粒子数**不是** <= 可通行格数：六角密排的间距是 2r = 0.926 格，
	#    所以每格平均放得下 ~1.34 个粒子。第一版这条断言写的是 made <= passable，
	#    在 276 格 / 366 粒子下直接误报 —— 而它误报的样子很像"掩码没生效"。
	#    真正的判据是"一个都没落在固体格里"，见下一条。
	_c("只把粒子排在可通行格里", made > 0 and _count_out_of_mask(circ) == 0,
		"%d 粒子 / %d 可通行格（密排密度 ~1.34/格）" % [made, passable])
	_c("初始粒子全在掩码内", _count_out_of_mask(circ) == 0)
	for i in 300:
		circ.step(0.0, 9.8)
	_c("300 步后粒子仍全在掩码内（没漂进固体）", _count_out_of_mask(circ) == 0,
		"%d 个越界" % _count_out_of_mask(circ))
	_c("异形容器里也不发散", _finite(circ))
	var ink_bad := 0
	for x in 24:
		for y in 24:
			if circ.ink[x * 24 + y] != 0 and circ.solid_mask[x * 24 + y] == 0:
				ink_bad += 1
	_c("ink 不越出掩码", ink_bad == 0, "%d 格越界" % ink_bad)
	# 固体那一半不该有任何 ink —— 圆形掩码下外接矩形的四角必然是空的
	var corner_ink := 0
	for x in [0, 1, 22, 23]:
		for y in [0, 1, 22, 23]:
			if circ.ink[x * 24 + y] != 0:
				corner_ink += 1
	_c("外接矩形的四角没有 ink", corner_ink == 0, "%d 格" % corner_ink)

	print("=== 原生 == 参照（逐位）===")
	if not ClassDB.class_exists("PixelFluid"):
		_s("逐位对拍", "PixelFluid 扩展未加载 —— 跑 python tools/build_native.py 重编 fastphys.dll")
	else:
		var a = _make(130)
		var b = _make(130)
		# 强制 b 走 GDScript 参照实现（否则两边都是原生，等于自己跟自己比）
		b._native_checked = true
		b._native = null
		for i in 200:
			a.step(0.0, 9.8)
			b.step(0.0, 9.8)
		# ⚠️ 用 %.17f 不用 %.17g —— GDScript 的 % 格式**没有 g**，写了会打
		#    "String formatting error: unsupported format character" 然后这一格空着。
		#    断言本身不受影响（判据是 ==），但看板会缺一格，很容易被当成"没跑"。
		# ⚠️⚠️ 先钉住"原生这条路真的走过"。
		#    原生失败会静默退回参照实现，那之后所有逐位断言都变成
		#    "GDScript 跟自己比"，必然通过 —— 闸门假绿。
		#    第一版没有这条，重编 DLL 失败时 36 项全绿，而原生一个字节都没测到。
		_c("a 走的是原生路径", a.native_calls > 0, "native_calls=%d" % a.native_calls)
		# ⚠️ 走原生时**权威状态在原生那边**，本文件的 pos/vel/rest_density 是旧的 ——
		#    比对之前必须先拉回来，否则比的是"GDScript 的僵值 vs 参照的活值"，
		#    必然全不同（第一版就是这样，报了 260/260 不同）。
		a.sync_from_native()
		_c("b 走的是参照实现", b.native_calls == 0, "native_calls=%d" % b.native_calls)
		_c("两边 rest_density 逐位相同", a.rest_density == b.rest_density,
			"%.17f vs %.17f" % [a.rest_density, b.rest_density])
		var diff := 0
		var first_bad := -1
		for i in a.pos.size():
			if a.pos[i] != b.pos[i]:
				diff += 1
				if first_bad < 0:
					first_bad = i
		_c("200 步后 pos 逐位相同", diff == 0, "%d/%d 个分量不同（首个 #%d）" % [
			diff, a.pos.size(), first_bad])
		var vdiff := 0
		for i in a.vel.size():
			if a.vel[i] != b.vel[i]:
				vdiff += 1
		_c("200 步后 vel 逐位相同", vdiff == 0, "%d/%d 个分量不同" % [vdiff, a.vel.size()])
		var ink_diff := 0
		for i in a.ink.size():
			if a.ink[i] != b.ink[i]:
				ink_diff += 1
		_c("200 步后 ink 掩码逐位相同", ink_diff == 0, "%d 格不同" % ink_diff)
		# 掉血路径也要对拍（增删粒子走的是 _select_extreme，它有哈希平局判据）
		var c1 = _make(130)
		var c2 = _make(130)
		c2._native_checked = true
		c2._native = null
		c1.fill_rate = 2
		c2.fill_rate = 2
		for i in 60:
			c1.step(0.0, 9.8)
			c2.step(0.0, 9.8)
		c1.set_fill_ratio(0.5)
		c2.set_fill_ratio(0.5)
		for i in 60:
			c1.step(0.0, 9.8)
			c2.step(0.0, 9.8)
		_c("掉血路径粒子数一致", c1.particle_count() == c2.particle_count(),
			"%d vs %d" % [c1.particle_count(), c2.particle_count()])
		c1.sync_from_native()
		var d2 := 0
		for i in mini(c1.pos.size(), c2.pos.size()):
			if c1.pos[i] != c2.pos[i]:
				d2 += 1
		_c("掉血路径 pos 逐位相同", d2 == 0 and c1.pos.size() == c2.pos.size(),
			"%d 个分量不同" % d2)
		# 异形容器也要对拍 —— _contain_particles / pbf_contain 是新增路径，
		# 而它里面有个"平局先扫到的赢"的判据，那正是最容易两边写岔的地方。
		var e1 = FluidPBF.new()
		var e2 = FluidPBF.new()
		# ⚠️ 循环变量不能叫 f —— _initialize 顶部已经有一个 var f，GDScript 不允许遮蔽
		for ef in [e1, e2]:
			ef.resize_grid(24, 24)
			for x in 24:
				for y in 24:
					var dx := (float(x) + 0.5) - 12.0
					var dy := (float(y) + 0.5) - 12.0
					ef.solid_mask[x * 24 + y] = 1 if dx * dx + dy * dy <= 90.25 else 0
			ef.init_particles(-1)
		e2._native_checked = true
		e2._native = null
		for i in 200:
			e1.step(0.0, 9.8)
			e2.step(0.0, 9.8)
		e1.sync_from_native()
		var d3 := 0
		for i in mini(e1.pos.size(), e2.pos.size()):
			if e1.pos[i] != e2.pos[i]:
				d3 += 1
		_c("异形容器 200 步 pos 逐位相同", d3 == 0 and e1.pos.size() == e2.pos.size(),
			"%d 个分量不同，粒子 %d vs %d" % [d3, e1.particle_count(), e2.particle_count()])

	print("")
	print("=== %d passed, %d failed, %d skipped ===" % [_pass, _fail, _skip])
	quit(0 if _fail == 0 else 1)


func _count_nonzero(a: PackedByteArray) -> int:
	var n := 0
	for v in a:
		if v != 0:
			n += 1
	return n

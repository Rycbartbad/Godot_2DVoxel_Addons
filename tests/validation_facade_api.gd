extends SceneTree
## 把开发者手册决策表里点名的**每个** px.* 接口真的调一遍。
##
## 为什么需要：check_manual_api.gd 只确认「方法存在」，不确认「调了有用」。
## 一个方法存在但行为不对（比如 spin 没累加、split_shape 返回空），
## 手册就成了一张空头支票 —— 而且不会有任何报错。
##
## 覆盖两张表：
##   力矩与动力学量：spin / torque_impulse / angular_velocity_of / momentum /
##                   angular_momentum / angular_momentum_about / kinetic_energy /
##                   mass_of / inertia_of / total_momentum / total_angular_momentum
##   破坏：carve_circle / carve_rect / cut / explode / split_shape / merge_shape / is_broken

## ⚠️ 必须对着**构建产物**跑，不能用 addon_src 里的模板 ——
##    模板里的路径是 res://addons/pixel_destruction/...，
##    那些路径要在 build_addon.py 里才被改写出来，直接 load 模板会报
##    「Preload file ... does not exist」。
##
##    所以 promote.py 会在跑测试前先在树内构建 addon，跑完再移出
##    （和 check_manual_api.gd 同一个约束）。
##
## ⚠️ 用 load() 而不是 preload()：addon 是构建产物，**平时不住在项目树里**，
##    preload 会让整个脚本在编辑器里直接解析失败（红字刷屏），而实际原因只是
##    "还没构建"。改成运行时加载 + 一句明确的失败信息，测试该红还是红，
##    但不再污染编辑器的错误面板。
const FACADE_PATH := "res://addons/pixel_destruction/pixel_physics.gd"

var _pass := 0
var _fail := 0
## addon 脚本对象。**类级变量**（不是 const preload）——
## preload 会在编辑器里直接解析失败，而原因只是"addon 还没构建"。
var Facade = null

func _c(n: String, ok: bool, d: String = "") -> void:
	if ok:
		_pass += 1
		print("  PASS  ", n, "  ", d)
	else:
		_fail += 1
		print("  FAIL  ", n, "  ", d)

func _mk() -> Node:
	var px = Facade.new()
	root.add_child(px)
	px.configure({"gravity": Vector2.ZERO})
	return px

func _initialize() -> void:
	Facade = load(FACADE_PATH)
	if Facade == null:
		print("  FAIL  找不到 %s —— 先跑 python tools/build_addon.py" % FACADE_PATH)
		print("=== 0 passed, 1 failed ===")
		quit(1)
		return
	await process_frame
	print("=== 力矩与动力学量 ===")
	var px = _mk()
	var b = px.spawn_rect(Vector2(0, 0), Vector2(32, 32), 1)
	await process_frame

	_c("mass_of", px.mass_of(b) > 0.0, "%.1f" % px.mass_of(b))
	_c("inertia_of", px.inertia_of(b) > 0.0, "%.1f" % px.inertia_of(b))

	# torque_impulse 是一次性的：立刻改变角速度
	var w0: float = px.angular_velocity_of(b)
	px.torque_impulse(b, 5000.0)
	var w1: float = px.angular_velocity_of(b)
	_c("torque_impulse 一次生效", absf(w1 - w0) > 1e-6, "%.4f -> %.4f" % [w0, w1])

	# spin 是持续力矩：每帧调，多帧后角速度持续增长
	# ⚠️ 别拿"10 帧持续力矩"和"一次性冲量"比大小 —— 一个是力矩、一个是角冲量，
	#    量纲都不同。第一版就是这么写的，于是把一个正常工作的 spin 判成了失败。
	#    正确的判据：从 0 起持续施加，角速度应当**单调增长**。
	px.set_angular_velocity(b, 0.0)
	px.spin(b, 2000.0)
	px.step(1.0 / 60.0)
	var w_1: float = px.angular_velocity_of(b)
	for i in 9:
		px.spin(b, 2000.0)
		px.step(1.0 / 60.0)
	var w_10: float = px.angular_velocity_of(b)
	_c("spin 持续施加（角速度单调增长）", w_1 > 1e-9 and w_10 > w_1,
		"1 帧 %.5f -> 10 帧 %.5f" % [w_1, w_10])
	px.clear_forces(b)

	# 动力学量：给一个已知的平动+转动
	px.set_velocity(b, Vector2(100, 0))
	px.set_angular_velocity(b, 2.0)
	var m: float = px.mass_of(b)
	var mo: Vector2 = px.momentum(b)
	_c("momentum = m*v", mo.is_equal_approx(Vector2(100.0 * m, 0.0)), str(mo))
	var I: float = px.inertia_of(b)
	var am: float = px.angular_momentum(b)
	_c("angular_momentum = I*w", absf(am - I * 2.0) < 1e-3, "%.3f vs %.3f" % [am, I * 2.0])
	_c("kinetic_energy > 0", px.kinetic_energy(b) > 0.0, "%.1f" % px.kinetic_energy(b))

	# 关于任意点的角动量：平动的物体关于远处一点应当有角动量
	var am_far: float = px.angular_momentum_about(b, Vector2(0, 1000))
	_c("angular_momentum_about 含 r×p 项", absf(am_far - am) > 0.1, "%.1f vs %.1f" % [am_far, am])

	# 守恒检查
	var tm: Vector2 = px.total_momentum()
	_c("total_momentum 与单体重心一致", tm.is_equal_approx(mo), str(tm))
	_c("total_angular_momentum 是数", px.total_angular_momentum() is float, "%.2f" % px.total_angular_momentum())

	print("=== 包围体（AABB 与凸包并列）===")
	# ⚠️ check_manual_api 只确认方法**存在**；这里确认"调了有用"。
	#    凸包这条尤其要紧：门面方法是**构建产物**里的那份（addon 路径），
	#    而它的行为依赖 src/core/hull_fit.gd 一起被拷过去 —— 漏拷就是运行时报错。
	var bx = px.spawn_rect(Vector2(400, 0), Vector2(40, 10), 1)
	await process_frame
	var ab: Rect2 = px.bounds(bx)
	_c("bounds 是 AABB", ab.size.x >= 40.0 and ab.size.y >= 10.0, str(ab))
	var hull: PackedVector2Array = px.hull(bx)
	_c("hull 给出凸包（至少 3 个顶点）", hull.size() >= 3, "%d 个顶点 %s" % [hull.size(), str(hull)])
	# 凸包必须**不比 AABB 大**（保守外接 + 紧）：面积判据
	var hull_area := 0.0
	for i in hull.size():
		var p: Vector2 = hull[i]
		var q: Vector2 = hull[(i + 1) % hull.size()]
		hull_area += p.x * q.y - q.x * p.y
	hull_area = absf(hull_area) * 0.5
	_c("凸包面积 <= AABB 面积（紧且保守）", hull_area <= ab.size.x * ab.size.y + 1e-3,
		"凸包 %.1f vs AABB %.1f" % [hull_area, ab.size.x * ab.size.y])
	_c("hull_contains 刚体质心", px.hull_contains(bx, px.center_of_mass(bx)))
	_c("hull_contains 远处为假", not px.hull_contains(bx, px.center_of_mass(bx) + Vector2(5000, 5000)))
	var sh: PackedVector2Array = px.shape_hull(bx.shapes[0])
	_c("shape_hull 是形状局部坐标的凸包", sh.size() >= 3, "%d 个顶点" % sh.size())
	var sb: Rect2i = px.shape_bounds(bx.shapes[0])
	# 局部凸包必须落在局部 AABB 内（保守性；用容差兜浮点）
	var inside := true
	for p2: Vector2 in sh:
		if not Rect2(Vector2(sb.position) - Vector2(0.001, 0.001),
				Vector2(sb.size) + Vector2(0.002, 0.002)).has_point(p2):
			inside = false
	_c("形状凸包落在形状 AABB 内", inside, "aabb=%s hull=%s" % [str(sb), str(sh)])

	print("=== 破坏 ===")
	# 挖圆洞
	var before: int = px.shape_voxels(b.shapes[0])
	# ⚠️ carve_* 返回的是**碎片数组**，不是挖掉的体素数（第一版赋给 int，运行时直接报错）
	var made: Array = px.carve_circle(Vector2(0, 0), 6.0)
	var after: int = px.shape_voxels(b.shapes[0])
	_c("carve_circle 真的挖掉了体素", after < before,
		"%d -> %d（返回 %d 个碎片）" % [before, after, made.size()])

	# 挖方洞
	var b2 = px.spawn_rect(Vector2(200, 0), Vector2(32, 32), 1)
	var n2: int = px.shape_voxels(b2.shapes[0])
	px.carve_rect(Vector2(200, 0), Vector2(8, 8))
	_c("carve_rect 真的挖掉了体素", px.shape_voxels(b2.shapes[0]) < n2,
		"%d -> %d" % [n2, px.shape_voxels(b2.shapes[0])])

	# 激光切割（把一块切成两半）
	var b3 = px.spawn_rect(Vector2(400, 0), Vector2(40, 40), 1)
	px.cut(Vector2(400, -60), Vector2(400, 60), 1.0)
	_c("cut 把方块切开了", px.shape_voxels(b3.shapes[0]) < 1600,
		"剩 %d 体素" % px.shape_voxels(b3.shapes[0]))

	# 爆炸（推开 + 破坏）
	var b4 = px.spawn_rect(Vector2(600, 0), Vector2(40, 40), 1)
	var n4: int = px.shape_voxels(b4.shapes[0])
	var frags: Array = px.explode(Vector2(600, 0), 80.0, 400.0)
	_c("explode 破坏了体素或产生了碎片", px.shape_voxels(b4.shapes[0]) < n4 or frags.size() > 0,
		"剩 %d 体素，%d 个碎片" % [px.shape_voxels(b4.shapes[0]), frags.size()])

	# ---- split_shape：必须造出**真的断开**的形状 ----
	#
	# ⚠️ 第一版造的形状根本没断开（挖空中间之后仍连通），于是只切出 1 块，
	#    而断言写的是 "parts is Array" —— **恒真**，等于没测。
	#    这正是我这一路反复栽的「绿的空壳」。
	#    现在：左右两个方块，中间 16 像素的空隙，必须切出 >= 2 块。
	# ⚠️ 这里不能调 clear_all() —— PixelShape 没有这个方法（第一版是我编的）。
	#    改成用一个**空形状**做底：create_shape(null) 就是空的。
	var split_src = px.create_shape(null)
	split_src.fill_rect(Rect2i(0, 0, 8, 8), 1)
	split_src.fill_rect(Rect2i(24, 0, 8, 8), 1)          # 与左边隔了 16 像素
	_c("（前置）形状确实不连通", px.is_shape_disconnected(split_src))
	var total_before: int = px.shape_voxels(split_src)
	var parts: Array = px.split_shape(split_src)
	# ⚠️ 语义是「**最大的那块留在原形状**，其余返回」——
	#    所以 parts 里**不包含**原形状留下的那块。
	#    第一版只累加 parts 再和总数比，于是把一个正确的实现判成了"丢体素"。
	#    真正的不变量：**原形状剩下的 + 返回的 = 原来的总数**。
	_c("split_shape 切出了另外的块", parts.size() >= 1, "%d 块" % parts.size())
	var total_after: int = px.shape_voxels(split_src)
	for p in parts:
		total_after += px.shape_voxels(p)
	_c("切分不丢体素（原形状剩下的 + 返回的）", total_after == total_before,
		"%d -> %d（原形状留 %d，返回 %d 块共 %d）"
		% [total_before, total_after, px.shape_voxels(split_src), parts.size(),
		   total_after - px.shape_voxels(split_src)])

	# ---- merge_shape：同一个形状里被拆开的相邻分块要合并回来 ----
	#
	# ⚠️ 第一版只传了一个本来就完整的形状，等于 no-op。
	#    这个接口的语义是「合并相邻形状（分块）」，所以先造碎块再合。
	var merge_src = px.create_shape(null)
	merge_src.fill_rect(Rect2i(0, 0, 4, 4), 1)
	merge_src.fill_rect(Rect2i(4, 0, 4, 4), 1)           # 紧挨着，应当被合并
	merge_src.fill_rect(Rect2i(0, 4, 8, 4), 1)
	var n_before: int = px.shape_voxels(merge_src)
	var merged = px.merge_shape(merge_src)
	_c("merge_shape 体素数不变", merged != null and px.shape_voxels(merged) == n_before,
		"%d -> %d" % [n_before, px.shape_voxels(merged) if merged != null else -1])
	_c("merge_shape 后仍然连通", merged != null and not px.is_shape_disconnected(merged))

	# ---- is_broken：必须**真的观察到 true** ----
	#
	# ⚠️ 第一版写的是 (not before) or after —— 恒真。挖了半天 broken_after 仍是 false，
	#    断言照样通过。现在要求：完整时 false、**挖空后 true**。
	var b5 = px.spawn_rect(Vector2(900, 0), Vector2(20, 20), 1)
	var broken_before: bool = px.is_broken(b5)
	px.carve_rect(Vector2(900, 0), Vector2(30, 30))      # 整块挖掉
	var broken_after: bool = px.is_broken(b5)
	_c("完整时 is_broken == false", not broken_before)
	_c("挖空后 is_broken == true", broken_after,
		"剩 %d 体素" % px.shape_voxels(b5.shapes[0]))

	print("=== 图片烘焙与固化 ===")
	# bake_image：8x8，左半红右半蓝 —— 关键主张是**逐像素材质**，必须真的验到两种
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.SKY_BLUE)
	for y in 8:
		for x in 4:
			img.set_pixel(x, y, Color.CRIMSON)
	var body_img = px.bake_image(img, Vector2(1200, 0), func(_x, _y, c) -> int:
		if c.a < 0.5:
			return 0
		return 1 if c.r > c.b else 2
	)
	_c("bake_image 造出刚体", body_img != null and px.shape_voxels(body_img.shapes[0]) == 64,
		"%d 体素" % px.shape_voxels(body_img.shapes[0]))
	var m_left: int = px.shape_material_at_index(body_img.shapes[0], 1, 1)
	var m_right: int = px.shape_material_at_index(body_img.shapes[0], 6, 1)
	_c("bake_image 是**逐像素**材质（不是整块一个）", m_left == 1 and m_right == 2,
		"左 %d 右 %d" % [m_left, m_right])

	# 透明像素必须不入形状
	var img_t := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img_t.fill(Color(1, 1, 1, 0))
	var body_t = px.bake_image(img_t, Vector2(1400, 0), func(_x, _y, c) -> int:
		return 0 if c.a < 0.5 else 1
	)
	_c("bake_image 透明像素不入形状",
		body_t == null or px.shape_voxels(body_t.shapes[0]) == 0,
		"%d 体素" % (px.shape_voxels(body_t.shapes[0]) if body_t != null else -1))

	# solidify：蓝图 -> 实体
	var r = px.renderer()
	var bp = px.make_circle(6.0, 1)
	var n_bp: int = px.shape_voxels(bp)
	r.sync_blueprint(9999, bp, Transform2D.IDENTITY)
	var body_s = px.solidify(9999, bp, Vector2(1600, 0))
	_c("solidify 造出实体", body_s != null and px.shape_voxels(body_s.shapes[0]) == n_bp,
		"蓝图 %d 体素 -> 实体 %d 体素" % [n_bp, px.shape_voxels(body_s.shapes[0])])

	# ---- 速度上限与灰尘策略：configure 的**每个新键**都必须真的生效 ----
	#
	# ⚠️ 为什么单独测：`configure` 的键是**字符串**，写错了不会报错（if opts.has 静默为假）——
	#    手册里承诺的旋钮就成了空头支票。判据是"世界上的值真的变了"。
	print("=== 速度上限与灰尘策略（configure 的键）==="
	)
	var px2 = Facade.new()
	root.add_child(px2)
	px2.configure({
		"max_linear_velocity": 12345.0,
		"max_angular_velocity": 50.0,
		"min_fragment_pixels": 9,
		"ccd_ignore_mass": 8.0,
		"debris_max_mass": 16.0,
		"debris_min_speed": 2000.0,
	})
	_c("max_linear_velocity 生效", px2.world.rp_max_linear_velocity == 12345.0,
		"%.0f" % px2.world.rp_max_linear_velocity)
	_c("max_angular_velocity 生效", px2.world.max_angular_velocity == 50.0,
		"%.0f" % px2.world.max_angular_velocity)
	_c("min_fragment_pixels 生效", px2.world.min_fragment_pixels == 9,
		"%d" % px2.world.min_fragment_pixels)
	_c("ccd_ignore_mass 生效", px2.world.ccd_ignore_mass == 8.0,
		"%.1f" % px2.world.ccd_ignore_mass)
	_c("灰尘阈值生效", px2.world.debris_max_mass == 16.0 and px2.world.debris_min_speed == 2000.0,
		"%.0f / %.0f" % [px2.world.debris_max_mass, px2.world.debris_min_speed])
	# 没给的键**不许乱动**（默认值原样）—— "没给" ≠ "设成 0"
	var px3 = Facade.new()
	root.add_child(px3)
	px3.configure({"gravity": Vector2.ZERO})
	_c("没给的键保持默认（角速度上限 1000）", px3.world.max_angular_velocity == 1000.0,
		"%.0f" % px3.world.max_angular_velocity)
	_c("没给的键保持默认（min_fragment_pixels 4 / 灰尘关）",
		px3.world.min_fragment_pixels == 4 and px3.world.debris_max_mass == 0.0 and px3.world.debris_min_speed == 0.0,
		"%d / %.0f / %.0f" % [px3.world.min_fragment_pixels, px3.world.debris_max_mass, px3.world.debris_min_speed])
	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

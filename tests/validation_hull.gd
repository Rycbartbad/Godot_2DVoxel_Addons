extends SceneTree
## 凸包（**多边形碰撞箱拟合**，与 AABB 并列的另一种包围体）验证。
##
## ## 参照物必须独立
##
## 本仓库在"缓存判错是不报错的"上栽过多次（HANDOFF 坑 6），所以这里的对拍**不用
## HullFit 自己的任何函数当预期值**：
##   · 凸包顶点集 -> **礼物包装（Jarvis）**，点集是"全部像素的四个角"（那边只取每行最左/最右）
##     —— 点集不同、算法不同、复杂度不同，没有共用一行；
##   · 点在多边形内 -> **Godot 原生 Geometry2D.is_point_in_polygon**（引擎实现，与 HullFit 无关）；
##   · 射线命中 -> **绕过 _ray_vs_body 的预剔除**，直接调体素 DDA。
##
## 最后一条尤其要紧：拿"被剔除过的结果"去对"被剔除过的结果"是同义反复。

const HullFit := preload("res://src/core/hull_fit.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const Query := preload("res://src/physics/query.gd")

var _pass := 0
var _fail := 0
func _c(n: String, ok: bool, d: String = "") -> void:
	if ok:
		_pass += 1
		print("  PASS  ", n, "  ", d)
	else:
		_fail += 1
		print("  FAIL  ", n, "  ", d)


# ============================================================ 参照实现（独立算法）

## 全部实心像素的四个角（暴力：逐格问 get_pixel，不碰任何内部结构）。
func _all_pixel_corners(shape: PixelShape) -> Array:
	var box := shape.local_aabb()
	var pts: Array = []
	for y in range(box.position.y, box.position.y + box.size.y):
		for x in range(box.position.x, box.position.x + box.size.x):
			if shape.get_pixel(x, y) == 0:
				continue
			pts.append(Vector2(x, y))
			pts.append(Vector2(x + 1, y))
			pts.append(Vector2(x, y + 1))
			pts.append(Vector2(x + 1, y + 1))
	return pts


## 礼物包装（Jarvis march）。O(n·h)。
## ⚠️ 共线时取**更远**的那个点 —— 这是"丢掉共线中间点"的标准写法，
##    与单调链的 <= 0 口径一致；不这么写会把一条直边上的每个点都当成顶点，
##    顶点集就对不上了（而那正是本测试要比的东西）。
func _ref_hull(pts: Array) -> PackedVector2Array:
	if pts.is_empty():
		return PackedVector2Array()
	var start: Vector2 = pts[0]
	for p: Vector2 in pts:
		if p.x < start.x or (p.x == start.x and p.y < start.y):
			start = p
	var hull := PackedVector2Array()
	var cur := start
	var guard := 0
	while true:
		guard += 1
		if guard > pts.size() + 4:
			break
		hull.append(cur)
		var next := Vector2.INF
		for p: Vector2 in pts:
			if p == cur:
				continue
			if next == Vector2.INF:
				next = p
				continue
			var cr := (next.x - cur.x) * (p.y - cur.y) - (next.y - cur.y) * (p.x - cur.x)
			if cr > 0.0 or (cr == 0.0 and cur.distance_squared_to(p) > cur.distance_squared_to(next)):
				next = p
		if next == Vector2.INF:
			break
		cur = next
		if cur == start:
			break
	return hull


## 把顶点列表规范化成"排序后的点集"，用来比较两个凸包的**顶点集**是否相同
## （起点/绕向可以不同，顶点集必须相同）。
func _vset(poly: PackedVector2Array) -> Array:
	var out: Array = []
	for p: Vector2 in poly:
		out.append([p.x, p.y])
	out.sort_custom(func(a: Array, b: Array) -> bool:
		return a[0] < b[0] if a[0] != b[0] else a[1] < b[1])
	return out


## 独立的点在多边形内判定：用**引擎**的 Geometry2D（不是 HullFit.contains）。
## ⚠️ 它按三角剖分做，点恰好落在边上时结果不定 —— 所以调用方只喂**严格内部**的点
##    （像素中心、以及像素内的 4 个亚采样点）。
func _inside_engine(poly: PackedVector2Array, p: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(p, poly)


## 两个凸包是不是同一个（**近似**判定）。
##
## ⚠️ 为什么不能比顶点集：刚体一转，角点就变成浮点数，"共线的三个点"在一边算出
##    叉积 0.0、在另一边算出 1e-16 —— 于是共线顶点一个被丢掉、一个被留下，
##    顶点集就不严格相等了。**那是浮点的性质，不是算错了**。
##    判据换成"面积近似相等 + 互相包含对方的顶点"。
func _same_hull_approx(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.size() < 3 or b.size() < 3:
		return a.size() == b.size()
	if absf(HullFit.area(a) - HullFit.area(b)) > 1.0e-3 * maxf(1.0, HullFit.area(b)):
		return false
	for p: Vector2 in a:
		if not HullFit.contains(b, p, 1.0e-3):
			return false
	for p: Vector2 in b:
		if not HullFit.contains(a, p, 1.0e-3):
			return false
	return true


## 每个顶点都是某个像素的角吗（"凸包没算大"的第一道判据）。
func _verts_are_pixel_corners(shape: PixelShape, hull: PackedVector2Array) -> bool:
	var corners := {}
	for p: Vector2 in _all_pixel_corners(shape):
		corners[str(p)] = true
	for p: Vector2 in hull:
		if not corners.has(str(p)):
			return false
	return true


## 每个顶点都**不能删**吗（"凸包没算大"的第二道判据：删掉它就会漏掉像素）。
## 用引擎的 is_point_in_polygon 判覆盖，与 HullFit 无关。
func _minimal(shape: PixelShape, hull: PackedVector2Array) -> bool:
	for skip in hull.size():
		var trimmed := PackedVector2Array()
		for i in hull.size():
			if i != skip:
				trimmed.append(hull[i])
		if trimmed.size() < 3:
			return false
		for y in range(shape.local_aabb().position.y, shape.local_aabb().position.y + shape.local_aabb().size.y):
			for x in range(shape.local_aabb().position.x, shape.local_aabb().position.x + shape.local_aabb().size.x):
				if shape.get_pixel(x, y) == 0:
					continue
				# 像素中心：删掉这个顶点之后必须**至少有一个**像素掉到外面
				if not _inside_engine(trimmed, Vector2(x + 0.5, y + 0.5)):
					return true
	return false


# ============================================================ 形状生成

func _disc(ox: int, oy: int, r: float) -> PixelShape:
	var s := PixelShape.new()
	for y in range(-int(ceil(r)), int(ceil(r)) + 1):
		for x in range(-int(ceil(r)), int(ceil(r)) + 1):
			if Vector2(x, y).length() <= r:
				s.set_pixel(ox + x, oy + y, 1)
	return s


## 五种形状：矩形 / 圆盘 / L 形（凹）/ 噪声 / 单像素宽斜线（退化）。
func _make_shape(kind: int, ox: int, oy: int, n: int) -> PixelShape:
	var s := PixelShape.new()
	match kind:
		0:
			s.fill_rect(Rect2i(ox, oy, n, maxi(1, n / 2)), 1)
		1:
			s = _disc(ox, oy, float(n) * 0.5)
		2:
			# L 形：凹，凸包会填掉内角 —— 正好验证"它只是包围体"
			s.fill_rect(Rect2i(ox, oy, n, 3), 1)
			s.fill_rect(Rect2i(ox, oy, 3, n), 1)
		3:
			var rng := RandomNumberGenerator.new()
			rng.seed = 0x5EED + kind * 31 + n
			for y in n:
				for x in n:
					if rng.randf() < 0.35:
						s.set_pixel(ox + x, oy + y, 1)
		4:
			for i in n:
				s.set_pixel(ox + i, oy + i, 1)
				s.set_pixel(ox + i + 1, oy + i, 1)
	return s


func _initialize() -> void:
	_test_basics()
	_test_properties()
	_test_cache()
	_test_body()
	_test_query_filter()
	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)


# ============================================================ 1. 基本形状（手算期望）

func _test_basics() -> void:
	# 单个像素：凸包是边长 1 的方形（像素是**单位方格**，不是格点）
	var one := PixelShape.new()
	one.set_pixel(3, 5, 1)
	var h1 := HullFit.fit(one)
	_c("单像素凸包是单位方格", _vset(h1) == _vset(PackedVector2Array([
		Vector2(3, 5), Vector2(4, 5), Vector2(3, 6), Vector2(4, 6)])), str(h1))
	_c("单像素凸包面积 = 1", is_equal_approx(HullFit.area(h1), 1.0), "%.4f" % HullFit.area(h1))

	# 空形状
	_c("空形状 -> 空凸包", HullFit.fit(PixelShape.new()).is_empty())

	# 2x3 实心矩形：凸包 = 那个矩形
	var rect := PixelShape.new()
	rect.fill_rect(Rect2i(0, 0, 2, 3), 1)
	var h2 := HullFit.fit(rect)
	_c("矩形凸包 = 自身", _vset(h2) == _vset(PackedVector2Array([
		Vector2(0, 0), Vector2(2, 0), Vector2(2, 3), Vector2(0, 3)])), str(h2))
	_c("矩形凸包面积 = 6", is_equal_approx(HullFit.area(h2), 6.0), "%.4f" % HullFit.area(h2))

	# 负坐标
	var neg := PixelShape.new()
	neg.fill_rect(Rect2i(-10, -7, 4, 3), 1)
	var h3 := HullFit.fit(neg)
	_c("负坐标凸包", _vset(h3) == _vset(PackedVector2Array([
		Vector2(-10, -7), Vector2(-6, -7), Vector2(-6, -4), Vector2(-10, -4)])), str(h3))

	# 共线点要丢掉（顶点数最小）
	var line := HullFit.of_points(PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(2, 0), Vector2(3, 0), Vector2(1.5, 2)]))
	_c("共线中间点被丢掉", line.size() == 3, str(line))

	# 绕向：signed_area > 0（屏幕上顺时针）。**钉住它** —— 下游按这个符号定外法线。
	_c("绕向固定（signed_area > 0）", HullFit.signed_area(h1) > 0.0,
		"%.2f" % HullFit.signed_area(h1))

	# 手算的三角：每行 x ∈ [0, y]
	var tri := PixelShape.new()
	for y in 8:
		for x in range(0, y + 1):
			tri.set_pixel(x, y, 1)
	var ht := HullFit.fit(tri)
	var aabb := tri.local_aabb()
	_c("阶梯三角的凸包比 AABB 紧", HullFit.area(ht) < float(aabb.size.x * aabb.size.y),
		"凸包 %.1f < AABB %d" % [HullFit.area(ht), aabb.size.x * aabb.size.y])
	_c("阶梯三角凸包面积 = 39.5（手算）", is_equal_approx(HullFit.area(ht), 39.5),
		"%.3f" % HullFit.area(ht))

	# contains / segment_hits 的手算用例
	var sq := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)])
	_c("contains 内部点", HullFit.contains(sq, Vector2(5, 5)))
	_c("contains 边上算内部", HullFit.contains(sq, Vector2(0, 5)))
	_c("contains 外部点", not HullFit.contains(sq, Vector2(5, 11)))
	_c("segment 穿过", HullFit.segment_hits(sq, Vector2(-5, 5), Vector2(15, 5)))
	_c("segment 未及", not HullFit.segment_hits(sq, Vector2(-5, 5), Vector2(-1, 5)))
	_c("segment 平行在外", not HullFit.segment_hits(sq, Vector2(-5, 20), Vector2(15, 20)))
	_c("segment 平行在外 + eps 够大 -> 命中", HullFit.segment_hits(sq, Vector2(-5, 20), Vector2(15, 20), 12.0))
	_c("segment 平行在外 + eps 不够 -> 不命中", not HullFit.segment_hits(sq, Vector2(-5, 20), Vector2(15, 20), 9.0))


# ============================================================ 2. 性质（对拍参照实现）

func _test_properties() -> void:
	var all_ok := {"vert": true, "cover": true, "conv": true, "tight": true, "min": true}
	var cases := 0
	for kind in 5:
		for n in [1, 3, 7, 12]:
			for off in [Vector2i(0, 0), Vector2i(-13, -9), Vector2i(40, 25)]:
				var s := _make_shape(kind, off.x, off.y, n)
				if s.is_empty():
					continue
				cases += 1
				var hull := HullFit.fit(s)
				var ref := _ref_hull(_all_pixel_corners(s))
				# (a) 与礼物包装**顶点集逐点相同**
				if _vset(hull) != _vset(ref):
					all_ok["vert"] = false
					print("     顶点集不一致 kind=%d n=%d off=%s\n       ours=%s\n       ref =%s"
						% [kind, n, str(off), str(hull), str(ref)])
				# (b) 覆盖：每个像素内 4 个亚采样点都在凸包内（引擎判定，独立）
				var box := s.local_aabb()
				var covered := true
				for y in range(box.position.y, box.position.y + box.size.y):
					for x in range(box.position.x, box.position.x + box.size.x):
						if s.get_pixel(x, y) == 0:
							continue
						for q: Vector2 in [Vector2(0.25, 0.25), Vector2(0.75, 0.25),
								Vector2(0.25, 0.75), Vector2(0.75, 0.75)]:
							if not _inside_engine(hull, Vector2(x, y) + q):
								covered = false
				if not covered:
					all_ok["cover"] = false
					print("     覆盖失败 kind=%d n=%d off=%s hull=%s" % [kind, n, str(off), str(hull)])
				# (c) 凸性：连续三点同号（严格左转，共线已被丢掉）
				var convex := true
				for i in hull.size():
					var a := hull[i]
					var b := hull[(i + 1) % hull.size()]
					var c := hull[(i + 2) % hull.size()]
					if (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x) <= 0.0:
						convex = false
				if not convex:
					all_ok["conv"] = false
					print("     凸性失败 kind=%d n=%d hull=%s" % [kind, n, str(hull)])
				# (d) 不比 AABB 大，且顶点都是像素角
				if HullFit.area(hull) > float(box.size.x * box.size.y) + 1e-6:
					all_ok["tight"] = false
				if not _verts_are_pixel_corners(s, hull):
					all_ok["tight"] = false
					print("     顶点不是像素角 kind=%d n=%d hull=%s" % [kind, n, str(hull)])
	_c("顶点集 == 礼物包装（%d 个用例）" % cases, all_ok["vert"])
	_c("覆盖所有像素（引擎判定，%d 个用例）" % cases, all_ok["cover"])
	_c("凸性（连续三点严格左转）", all_ok["conv"])
	_c("不比 AABB 大 + 顶点都是像素角", all_ok["tight"])

	# 最小性：随便删一个顶点就会漏像素（只挑小形状，代价是 O(V·像素数)）
	var small := _make_shape(1, 0, 0, 9)
	var hs := HullFit.fit(small)
	_c("最小性：删任一顶点即漏像素", _minimal(small, hs), "顶点 %d 个" % hs.size())


# ============================================================ 3. 缓存失效

func _test_cache() -> void:
	# ⚠️⚠️ 这一条是本文件里**最要紧**的回归闸门：
	#    "平顶"形状上擦掉一个凸包顶点，AABB **一个边界都不动** ——
	#    如果凸包缓存挂在 _bounds_rev 上（像 AABB 那样），这里就会静默返回旧凸包。
	#
	#    形状：y=0..100，每行 x ∈ [50-half, 60+half]，half = min(y, 100-y)
	#    （平顶六边形：顶边宽 11，最宽处 y=50 时 x ∈ [0,110]）
	var s := PixelShape.new()
	for y in 101:
		var half := mini(y, 100 - y)
		s.fill_rect(Rect2i(50 - half, y, (60 + half) - (50 - half) + 1, 1), 1)
	var aabb_before := s.local_aabb()
	var h_before := HullFit.fit(s)
	_c("平顶形状：顶点 (50,0) 在凸包里",
		_vset(h_before).has([50.0, 0.0]), str(h_before))
	s.clear_pixel(50, 0)
	var aabb_after := s.local_aabb()
	var h_after := s.local_hull()
	_c("擦掉顶点像素后 AABB **不变**（这正是坑）", aabb_before == aabb_after,
		"%s -> %s" % [str(aabb_before), str(aabb_after)])
	_c("擦掉顶点像素后凸包**必须变**", _vset(h_after) != _vset(h_before),
		"%s -> %s" % [str(h_before), str(h_after)])
	_c("新凸包不再含 (50,0)", not _vset(h_after).has([50.0, 0.0]), str(h_after))
	_c("新凸包仍覆盖全部像素", _vset(h_after) == _vset(_ref_hull(_all_pixel_corners(s))), str(h_after))

	# 内部挖洞**不该**改变凸包（凸包只看外轮廓）
	var b := PixelShape.new()
	b.fill_rect(Rect2i(0, 0, 20, 20), 1)
	var h0 := b.local_hull()
	b.clear_pixel(10, 10)
	_c("内部挖洞不改变凸包", _vset(b.local_hull()) == _vset(h0), str(b.local_hull()))

	# 连续两次调用必须返回同一份结果（缓存命中路径也要对）
	var again := b.local_hull()
	_c("缓存命中结果一致", _vset(again) == _vset(b.local_hull()))


# ============================================================ 4. 刚体上的凸包

func _test_body() -> void:
	var s := _make_shape(2, 0, 0, 24)          # L 形（凹）
	var b := PBody.new()
	b.position = Vector2(100, 50)
	b.rebuild([s])
	# (a) 局部凸包 == 像素凸包（rects 是**精确覆盖**，所以两者逐点相同）
	#     这是"两条独立来源"的交叉验证：一边走 rects 角点，一边走像素角点。
	_c("刚体局部凸包 == 像素凸包（rects 精确覆盖）",
		_vset(b.local_hull()) == _vset(HullFit.fit(s)),
		"%s vs %s" % [str(b.local_hull()), str(HullFit.fit(s))])
	# (b) 世界凸包 == 局部凸包按位姿变换（手算变换，独立）
	var wh := b.world_hull()
	var c := cos(b.rotation)
	var sn := sin(b.rotation)
	var manual := PackedVector2Array()
	for p: Vector2 in b.local_hull():
		manual.append(Vector2(b.position.x + p.x * c - p.y * sn, b.position.y + p.x * sn + p.y * c))
	_c("世界凸包 == 局部凸包按位姿变换", _vset(wh) == _vset(manual), str(wh))
	# (c) 凸包 ⊆ AABB（保守性）
	var inside := true
	for p: Vector2 in wh:
		if not b.aabb.grow(0.001).has_point(p):
			inside = false
	_c("世界凸包落在 AABB 内", inside, "aabb=%s hull=%s" % [str(b.aabb), str(wh)])
	# (d) 每个碰撞矩形的角都在凸包里（**保守性**：矩形是物理真形状）
	var covers := true
	for r: Rect2 in b.rects:
		for p2: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
			if not HullFit.contains(wh, b.to_world(p2), 0.001):
				covers = false
	_c("凸包包住每个碰撞矩形（保守性）", covers)

	# (e) 位姿变化必须让世界凸包失效 —— 只查 rects_rev 的写法会在这里翻车
	b.rotation = 0.7
	b.position = Vector2(-30, 12)
	var wh2 := b.world_hull()
	_c("移动/旋转后世界凸包跟着变", _vset(wh2) != _vset(wh), str(wh2))
	_c("移动/旋转后仍然对（与参照凸包近似一致）",
		_same_hull_approx(wh2, _ref_hull(_all_pixel_corners_rotated(b))),
		"%s vs %s" % [str(wh2), str(_ref_hull(_all_pixel_corners_rotated(b)))])

	# (f) 破坏后局部凸包必须失效（rects_rev 变）
	var b2 := PBody.new()
	var s2 := PixelShape.new()
	s2.fill_rect(Rect2i(0, 0, 30, 10), 1)
	b2.rebuild([s2])
	var lh0 := b2.local_hull()
	s2.fill_rect(Rect2i(20, -10, 5, 5), 1)     # 右上角长出一个角
	b2.rebuild([s2])
	_c("内容变化后局部凸包跟着变", _vset(b2.local_hull()) != _vset(lh0),
		"%s -> %s" % [str(lh0), str(b2.local_hull())])

	# (h) 机会主义契约：**没算过时绝不重算**（返回空），算过之后给同一份，重建后立刻作废
	var b4 := PBody.new()
	b4.rebuild([_disc(0, 0, 5.0)])
	_c("没算过时 cached_local_hull 为空（不触发重算）", b4.cached_local_hull().is_empty())
	var h4 := b4.local_hull()
	_c("算过之后 cached_local_hull 给同一份", _vset(b4.cached_local_hull()) == _vset(h4))
	b4.rebuild(b4.shapes)
	_c("重建后立刻作废（不拿旧凸包）", b4.cached_local_hull().is_empty())

	# (g) hull_contains：质心在内、远处在外
	var b3 := PBody.new()
	b3.position = Vector2(7, 7)
	b3.rebuild([_disc(0, 0, 10.0)])
	_c("hull_contains 质心", b3.hull_contains(b3.com_world()))
	_c("hull_contains 远处", not b3.hull_contains(b3.com_world() + Vector2(500, 500)))


## 刚体的像素角点**转到世界**（给参照凸包用）。
func _all_pixel_corners_rotated(b: PBody) -> Array:
	var out: Array = []
	for s in b.shapes:
		for p: Vector2 in _all_pixel_corners(s):
			out.append(b.to_world(p))
	return out


# ============================================================ 5. 射线预剔除（保守性）

## 绕过 _ray_vs_body 的凸包预剔除的**参照射线**：直接走体素 DDA / 扫掠圆。
func _ref_raycast(w: PWorld, origin: Vector2, dir: Vector2, max_dist: float,
		radius: float, reject: Array) -> Query.Hit:
	var best := Query._hit_none()
	best.distance = max_dist
	for b: PBody in w.bodies:
		if b.rects.is_empty() or reject.has(b):
			continue
		var h: Query.Hit = null
		if radius > 0.0:
			h = Query._swept_circle_vs_body(b, origin, dir, max_dist, radius)
		else:
			h = Query._hit_none()
			var lo := b.to_local(origin)
			var ld := dir.rotated(-b.rotation)
			var best_t := max_dist
			for s in b.shapes:
				var hh := Query._dda(s, lo, ld, best_t)
				if hh.hit and hh.distance < best_t:
					best_t = hh.distance
					h = hh
					h.shape = s
					h.body = b
			if h.hit:
				h.point = b.to_world(h.point)
				h.normal = h.normal.rotated(b.rotation)
		if h != null and h.hit and h.distance < best.distance:
			best = h
	return best


## 撒 n 条随机射线，把 Query.raycast（含预剔除）与**绕过它的参照**逐项对拍。
##
## 返回 {"mismatch": 不一致的条数, "filtered": 被凸包挡掉的（刚体,射线）对数}。
## ⚠️ 射线覆盖四个象限（方向朝上/朝左也在内）—— 粗筛包围盒算错时**只有朝上/朝左会漏**，
##    只测朝右/朝下的射线等于没测（见 Query.raycast 里那段墓碑）。
func _sweep_rays(w: PWorld, n: int, seed_v: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var mismatches := 0
	var filtered := 0
	for i in n:
		var o := Vector2(rng.randf_range(-160, 160), rng.randf_range(-120, 120))
		var ang := rng.randf_range(-PI, PI)
		var d := Vector2(cos(ang), sin(ang))
		var md := rng.randf_range(20.0, 400.0)
		var radius := 0.0 if i % 3 != 0 else rng.randf_range(1.0, 6.0)
		var got := Query.raycast(o, d, md, radius)
		var ref := _ref_raycast(w, o, d.normalized(), md, radius, [])
		# 命中与否、距离、材质必须**逐项一致**（预剔除只要误杀一次，这里就红）
		var same := got.hit == ref.hit
		if same and got.hit:
			same = is_equal_approx(got.distance, ref.distance) and got.material == ref.material
		if not same:
			mismatches += 1
			if mismatches <= 3:
				print("     不一致 o=%s d=%s md=%.1f r=%.2f got(hit=%s d=%.3f mat=%d) ref(hit=%s d=%.3f mat=%d)"
					% [str(o), str(d), md, radius, str(got.hit), got.distance, got.material,
						str(ref.hit), ref.distance, ref.material])
		# 统计"被凸包挡掉"的机会数（与 raycast 内部同一条判据，只是这里在数）
		var far := o + d.normalized() * md
		var pd := maxf(radius, 1.0)
		var box := Rect2(Vector2(minf(o.x, far.x), minf(o.y, far.y)) - Vector2(pd, pd),
			Vector2(absf(far.x - o.x), absf(far.y - o.y)) + Vector2(pd, pd) * 2.0)
		box.size = Vector2(maxf(box.size.x, 1.0), maxf(box.size.y, 1.0))
		for b2: PBody in w.bodies:
			if b2.rects.is_empty() or not box.intersects(b2.aabb):
				continue
			var h2 := b2.cached_local_hull()
			if h2.is_empty():
				continue
			var l2 := b2.to_local(o)
			if not HullFit.segment_hits(h2, l2, l2 + d.rotated(-b2.rotation).normalized() * md,
					radius + 1.5):
				filtered += 1
	return {"mismatch": mismatches, "filtered": filtered}


func _test_query_filter() -> void:
	var w := PWorld.new()
	w.gravity = Vector2.ZERO
	# 一块地面 + 一块**转 45 度**的薄板（AABB 会膨胀成一个几乎全空的方框）+ 几个碎片
	var gs := PixelShape.new()
	gs.fill_rect(Rect2i(-200, 0, 400, 20), 3)
	var ground := PBody.new()
	ground.make_static()
	ground.position = Vector2(0, 200)
	w.add_body(ground, [gs])

	var plank := PBody.new()
	plank.make_static()
	plank.position = Vector2(0, 0)
	plank.rotation = PI * 0.25
	var ps := PixelShape.new()
	ps.fill_rect(Rect2i(-60, -3, 120, 6), 2)
	w.add_body(plank, [ps])

	var debris := PBody.new()
	debris.position = Vector2(40, -40)
	w.add_body(debris, [_disc(0, 0, 6.0)])

	Query.attach(w)
	# ⚠️ 预剔除是**机会主义**的（只在凸包已经算过时参与，见 Query._ray_vs_body），
	#    所以**两条路都要对拍**：
	#      · 冷路径：一个凸包都没算过 -> 退化成 AABB（这也是"没人在乎凸包"的项目走的路）
	#      · 热路径：算过之后真的参与剔除
	#    两者的**结果必须完全一样**（变的只是快慢）；热路径还要能证明它真的挡掉了东西。
	var cold := _sweep_rays(w, 120, 4242)
	_c("冷路径（凸包没算过）：结果与参照一致", cold["mismatch"] == 0,
		"不一致 %d 条" % cold["mismatch"])
	for b: PBody in w.bodies:
		b.local_hull()          # 焐热：编辑器抓手 / 调试叠加层 / 游戏层调 px.hull() 都会走到这一步
	var warm := _sweep_rays(w, 300, 20260418)
	_c("热路径（凸包算过）：结果与参照一致", warm["mismatch"] == 0,
		"不一致 %d 条" % warm["mismatch"])
	_c("凸包预剔除确实在挡东西（不是死代码）", warm["filtered"] > 0,
		"挡掉 %d 个（刚体,射线）对" % warm["filtered"])

	# 旋转薄板：AABB 面积 / 凸包面积 的比值应该明显大于 1（这正是这条预剔除的意义）
	var aabb_area := plank.aabb.size.x * plank.aabb.size.y
	var hull_area := HullFit.area(plank.world_hull())
	_c("转 45 度的薄板：凸包比 AABB 紧得多", hull_area * 2.0 < aabb_area,
		"凸包 %.0f vs AABB %.0f" % [hull_area, aabb_area])

	Query.detach(w)

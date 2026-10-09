extends SceneTree
## **碰撞体多边形拟合**（Noita 式）的闸门。
##
## 守三件事：
##   1. **拟合的性质**：覆盖（每个像素都在某个多边形里）、凸性、偏离预算、确定性；
##   2. **原生与参照一致**：同一份矩形集合 -> 同一组多边形（本仓库对"两条路"的规矩）；
##   3. **物理真的用它**：质量不分叉（拟合后碰撞体面积变大，密度必须按质量反算）、
##      锯齿楼梯的斜边真的被拉直（块数从 40 掉到 1，且边不是轴对齐的）。
##
## ⚠️ 参照物独立：性质用 GDScript 的 PolyFit（自己写的第二份实现）与**几何定义**
##    （凸性/覆盖/偏离都是逐条验算，不拿引擎的说法当预期值）。

const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const PolyFit := preload("res://src/core/poly_fit.gd")
const GreedyRects := preload("res://src/core/greedy_rects.gd")

var _pass := 0
var _fail := 0
func _c(n: String, ok: bool, d: String = "") -> void:
	if ok:
		_pass += 1
		print("  PASS  ", n, "  ", d)
	else:
		_fail += 1
		print("  FAIL  ", n, "  ", d)


func _stair(n: int) -> PixelShape:
	var s := PixelShape.new()
	for y in n:
		for x in range(0, n - y):
			s.set_pixel(x, y, 1)
	return s


func _disc(r: float) -> PixelShape:
	var s := PixelShape.new()
	for y in range(-int(ceil(r)), int(ceil(r)) + 1):
		for x in range(-int(ceil(r)), int(ceil(r)) + 1):
			if Vector2(x, y).length() <= r:
				s.set_pixel(x, y, 1)
	return s


func _wall_hole() -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, 60, 60), 1)
	s.fill_rect(Rect2i(24, 24, 12, 12), 0)
	return s


## 独立实现：点在**闭凸多边形**内（自己算绕向 + 逐边叉积同号）。
func _in_poly(poly: PackedVector2Array, p: Vector2) -> bool:
	var lo := INF
	var hi := -INF
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var c := (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
		lo = minf(lo, c)
		hi = maxf(hi, c)
	return lo >= 0.0 or hi <= 0.0


func _is_convex(poly: PackedVector2Array) -> bool:
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var c := poly[(i + 2) % poly.size()]
		if (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x) <= 0.0:
			return false
	return true


## 有多边形的一条边**不是**轴对齐的吗（"锯齿被拉直"的结构判据）。
func _has_diagonal(poly: PackedVector2Array) -> bool:
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		if absf(a.x - b.x) > 1.0e-4 and absf(a.y - b.y) > 1.0e-4:
			return true
	return false


func _initialize() -> void:
	_test_fit_properties()
	_test_hole()
	_test_native_matches_reference()
	_test_physics()
	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)


# ---------------------------------------------------------------- 1. 拟合性质

func _test_fit_properties() -> void:
	var cases: Array = [
		["楼梯 40", _stair(40)],
		["圆盘 r=20", _disc(20.0)],
		["斜线 1px", _diag()],
		["墙+洞", _wall_hole()],
		["噪声", _noise()],
		["L 形", _lshape()],
	]
	var ok_cover := true
	var ok_convex := true
	var ok_dev := true
	var ok_contains_rects := true
	for pair: Array in cases:
		var name: String = pair[0]
		var s: PixelShape = pair[1]
		var res: PolyFit.Result = PolyFit.decompose(s, PolyFit.DEFAULT_DEV_TOL)
		if res.parts() == 0:
			ok_cover = false
			print("     %s: 没有多边形" % name)
			continue
		# 覆盖：每个像素中心都落在某个多边形里（凸多边形包含判定，独立实现）
		var box := s.local_aabb()
		for y in range(box.position.y, box.position.y + box.size.y):
			for x in range(box.position.x, box.position.x + box.size.x):
				if s.get_pixel(x, y) == 0:
					continue
				var c := Vector2(x + 0.5, y + 0.5)
				var hit := false
				for p: PackedVector2Array in res.polys:
					if _in_poly(p, c):
						hit = true
						break
				if not hit:
					ok_cover = false
					print("     %s: 像素 (%d,%d) 没被任何多边形盖住" % [name, x, y])
					break
		# 凸性
		for p2: PackedVector2Array in res.polys:
			if not _is_convex(p2):
				ok_convex = false
				print("     %s: 有多边形不是凸的 %s" % [name, str(p2)])
		# 偏离预算
		if res.max_deviation > PolyFit.DEFAULT_DEV_TOL + 1.0e-6:
			ok_dev = false
			print("     %s: 偏离 %.3f 超预算" % [name, res.max_deviation])
		# 每个**碰撞矩形**的四个角都在某个多边形里（保守性：碰撞体不许比像素小）
		var rects: Array = GreedyRects.decompose(s, 0).rects
		for r: Rect2 in rects:
			for corner: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
				var inside := false
				for p3: PackedVector2Array in res.polys:
					if _in_poly(p3, corner):
						inside = true
						break
				if not inside:
					ok_contains_rects = false
					print("     %s: 矩形角 %s 不在任何多边形里" % [name, str(corner)])
	_c("每个像素都被某个多边形盖住", ok_cover)
	_c("每个多边形都是凸的", ok_convex)
	_c("偏离不超过容差（%.1f px）" % PolyFit.DEFAULT_DEV_TOL, ok_dev)
	_c("每个碰撞矩形都被包住（保守性）", ok_contains_rects)

	# 楼梯：**一块**，而且有斜边（这就是这次改动的目的）
	var st: PixelShape = _stair(40)
	var rs: PolyFit.Result = PolyFit.decompose(st, PolyFit.DEFAULT_DEV_TOL)
	var rects_n: int = GreedyRects.decompose(st, 0).rects.size()
	_c("楼梯拟合成一块（矩形 %d 个）" % rects_n, rs.parts() == 1, "%d 块" % rs.parts())
	_c("楼梯的边不是轴对齐的（锯齿被拉直）", _has_diagonal(rs.polys[0]), str(rs.polys[0]))
	_c("楼梯的偏离 < 1 像素", rs.max_deviation < 1.0, "%.3f" % rs.max_deviation)

	# 确定性：同一份矩形集合 -> 同一组多边形（与输入顺序无关）
	var shuffled: Array = GreedyRects.decompose(st, 0).rects.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in range(shuffled.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = tmp
	var a: PolyFit.Result = PolyFit.decompose_rects(GreedyRects.decompose(st, 0).rects, 2.0)
	var b: PolyFit.Result = PolyFit.decompose_rects(shuffled, 2.0)
	_c("打乱矩形顺序结果不变（确定性）", str(a.polys) == str(b.polys), "%d vs %d 块" % [a.parts(), b.parts()])


# ---------------------------------------------------------------- 2. 洞

func _test_hole() -> void:
	var s: PixelShape = _wall_hole()
	var res: PolyFit.Result = PolyFit.decompose(s, PolyFit.DEFAULT_DEV_TOL)
	var covered := false
	for p: PackedVector2Array in res.polys:
		if _in_poly(p, Vector2(30, 30)):
			covered = true
	_c("墙上的洞不会被封死（结构上保住）", not covered,
		"%d 块，洞中心被盖住=%s" % [res.parts(), str(covered)])


# ---------------------------------------------------------------- 3. 原生 == 参照

func _test_native_matches_reference() -> void:
	var w := PWorld.new()
	var s: PixelShape = _stair(40)
	var b := PBody.new()
	b.make_static()
	w.add_body(b, [s])
	w.step(1.0 / 60.0)          # 走一步，碰撞体才会被推给 Rapier
	var native: Array = w.fetch_polys(b)
	var ref: PolyFit.Result = PolyFit.decompose(s, w.poly_dev_tol)
	_c("原生拟合的块数 == 参照实现", native.size() == ref.parts(),
		"原生 %d vs 参照 %d" % [native.size(), ref.parts()])
	var same := native.size() == ref.parts()
	if same:
		for i in native.size():
			var a: PackedVector2Array = native[i]
			var b2: PackedVector2Array = ref.polys[i]
			if a.size() != b2.size():
				same = false
				break
			for k in a.size():
				if not a[k].is_equal_approx(b2[k]):
					same = false
					break
	_c("原生拟合的顶点 == 参照实现（逐点）", same,
		"原生 %s vs 参照 %s" % [str(native), str(ref.polys)])


# ---------------------------------------------------------------- 4. 物理

func _test_physics() -> void:
	var w := PWorld.new()
	var gs := PixelShape.new()
	gs.fill_rect(Rect2i(0, 0, 400, 20), 1)
	var ground := PBody.new()
	ground.make_static()
	ground.position = Vector2(-100, 200)
	w.add_body(ground, [gs])
	var bs := PixelShape.new()
	bs.fill_rect(Rect2i(0, 0, 16, 16), 1)
	var box := PBody.new()
	box.position = Vector2(0, -100)
	w.add_body(box, [bs])
	for i in 180:
		w.step(1.0 / 60.0)
	_c("方块落在地面上停住（多边形碰撞体真的参与求解）",
		box.linear_velocity.length() < 1.0 and absf(box.position.y - 184.0) < 1.0,
		"位置 %s 速度 %s" % [str(box.position), str(box.linear_velocity)])
	# 质量不许分叉：拟合后碰撞体面积 >= 像素面积，密度按质量反算
	var rm: float = w.rp_body_mass(box)
	_c("Rapier 的质量 == GDScript 的 mass（密度补偿生效）",
		rm > 0.0 and absf(rm - box.mass) < maxf(0.01, box.mass * 1.0e-4),
		"Rapier %.3f vs GDScript %.3f" % [rm, box.mass])
	# 块数确实变少了（这次改动的意义）
	var polys: Array = w.fetch_polys(ground)
	_c("实心地面的碰撞体是 1 个多边形（矩形 1 个，但不再有内部接缝）",
		polys.size() == 1, "%d 个" % polys.size())
	# 矩形退回路径：仍然可用、质量仍然对
	var w2 := PWorld.new()
	w2.poly_colliders = false
	var gs2 := PixelShape.new()
	gs2.fill_rect(Rect2i(0, 0, 200, 20), 1)
	var g2 := PBody.new()
	g2.make_static()
	g2.position = Vector2(0, 100)
	w2.add_body(g2, [gs2])
	var b2s := PixelShape.new()
	b2s.fill_rect(Rect2i(0, 0, 10, 10), 1)
	var b2 := PBody.new()
	b2.position = Vector2(0, 0)
	w2.add_body(b2, [b2s])
	for i in 120:
		w2.step(1.0 / 60.0)
	var rm2: float = w2.rp_body_mass(b2)
	_c("关掉多边形拟合（退回矩形）时质量同样不分叉",
		rm2 > 0.0 and absf(rm2 - b2.mass) < maxf(0.01, b2.mass * 1.0e-4),
		"Rapier %.3f vs GDScript %.3f" % [rm2, b2.mass])
	var rp: Array = w2.fetch_polys(b2)
	_c("退回路径读回的是矩形（4 个角）", rp.size() == 1 and (rp[0] as PackedVector2Array).size() == 4,
		"%d 个，顶点数 %s" % [rp.size(), str(rp.map(func(p): return p.size()))])


func _diag() -> PixelShape:
	var s := PixelShape.new()
	for i in 40:
		s.set_pixel(i, i, 1)
	return s


func _noise() -> PixelShape:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var s := PixelShape.new()
	for y in 24:
		for x in 24:
			if rng.randf() < 0.55:
				s.set_pixel(x, y, 1)
	return s


func _lshape() -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, 40, 8), 1)
	s.fill_rect(Rect2i(0, 0, 8, 40), 1)
	return s

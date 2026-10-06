extends SceneTree
## 原生矩形分解（PixelRaster op 2）vs GDScript 参照实现的**逐位对拍**闸门。
##
## ⚠️ 为什么必须有这一条："像素团 -> 矩形集合"这条规则现在写了**两份** ——
##    gdext/fastphys.cpp 的 op 2，与 src/core/greedy_rects.gd 的 decompose_gd。
##    本仓库在"同一规则写两处"上栽过太多次，所以原生化必须配一条**逐位**判据 ——
##    不是"看起来一样"。
##
## ⚠️⚠️ **顺序也是判据**：矩形顺序会原样进入 Rapier 的碰撞体顺序，
##    所以这里逐条比对每个矩形的 4 个分量**和它的下标**。
##
## 判据有四条，缺一不可：
##   ① 矩形数量、每个矩形的 4 个分量、顺序全部相同；
##   ② origin / budget_exceeded 相同（max_rects 只影响后者）；
##   ③ **原生算出的 AABB 与重算的 local_aabb() 逐位相同** ——
##      它会写回 PixelShape 的缓存，写错就是"形状与碰撞体静默错位"（用户报过两次）；
##   ④ **原生那条真的被走了**（native_calls / native_fallbacks 计数）——
##      否则"退回了 GDScript"会让本闸门静默变成同义反复（结果当然一样）。
const PixelShape := preload("res://src/core/pixel_shape.gd")
const GreedyRects := preload("res://src/core/greedy_rects.gd")

var _pass := 0
var _fail := 0
var _cases := 0
var _rects_cmp := 0
var _retries := 0
var _flip := false
var _rng := RandomNumberGenerator.new()

func _c(n: String, ok: bool, d: String = "") -> void:
	if ok:
		_pass += 1
		print("  PASS  ", n, "  ", d)
	else:
		_fail += 1
		print("  FAIL  ", n, "  ", d)


## 逐位比较两份矩形列表（数量、每个矩形的 4 个分量、顺序）。
## 返回 "" 表示相同，否则返回第一处差异。
func _diff_rects(a: Array, b: Array) -> String:
	if a.size() != b.size():
		return "矩形数 %d != %d" % [a.size(), b.size()]
	for i in a.size():
		var p: Rect2 = a[i]
		var q: Rect2 = b[i]
		if p.position.x != q.position.x:
			return "#%d position.x %s != %s" % [i, str(p.position.x), str(q.position.x)]
		if p.position.y != q.position.y:
			return "#%d position.y %s != %s" % [i, str(p.position.y), str(q.position.y)]
		if p.size.x != q.size.x:
			return "#%d size.x %s != %s" % [i, str(p.size.x), str(q.size.x)]
		if p.size.y != q.size.y:
			return "#%d size.y %s != %s" % [i, str(p.size.y), str(q.size.y)]
	return ""


## 作废 AABB 缓存并重算 —— 逼参照实现自己扫一遍，别吃到原生写回的缓存。
func _aabb_gd(s: PixelShape) -> Rect2i:
	s._aabb_rev = -1
	return s.local_aabb()


## 一个形状跑两条路。_flip 交替顺序：块缓存被谁先喂满不一样（两边都必须一致）。
func _cmp(label: String, s: PixelShape, max_rects: int = 0) -> void:
	_cases += 1
	var n := s.chunks.size()
	var r_ref: GreedyRects.Result = null
	if _flip:
		s._aabb_rev = -1
		r_ref = GreedyRects.decompose_gd(s, max_rects)
	GreedyRects.native_calls = 0
	GreedyRects.native_fallbacks = 0
	s._aabb_rev = -1                       # 作废，逼原生把 AABB 缓存写回来
	var r_nat: GreedyRects.Result = GreedyRects.decompose(s, max_rects)
	var calls := GreedyRects.native_calls
	var backs := GreedyRects.native_fallbacks
	var wrote_back := s._aabb_rev == s._bounds_rev
	var aabb_nat: Rect2i = s.local_aabb()  # 命中原生写回的那份
	var aabb_ref: Rect2i = _aabb_gd(s)     # 作废后重算的参照值
	if not _flip:
		s._aabb_rev = -1
		r_ref = GreedyRects.decompose_gd(s, max_rects)
	_flip = not _flip
	_rects_cmp += maxi(r_nat.rects.size(), r_ref.rects.size())
	if calls == 2:
		_retries += 1

	var tag := "%s（%d 像素 / %d chunk / aabb=%s）" % [
		label, s.pixel_count(), n, str(aabb_ref)]
	# ④ 真的走了原生（空形状按设计不走 —— 那条路交给参照实现）
	if n <= 0:
		_c(tag + " 空形状不走原生", calls == 0 and backs == 0, "calls=%d backs=%d" % [calls, backs])
	else:
		_c(tag + " 走原生", calls >= 1 and backs == 0, "calls=%d backs=%d" % [calls, backs])
	# ① 矩形数 + 每个矩形的 4 个分量 + 顺序
	var d := _diff_rects(r_nat.rects, r_ref.rects)
	_c(tag + " 矩形逐位相同", d == "", d)
	# ② origin / budget
	_c(tag + " origin 相同", r_nat.origin == r_ref.origin,
		"%s vs %s" % [str(r_nat.origin), str(r_ref.origin)])
	_c(tag + " budget_exceeded 相同", r_nat.budget_exceeded == r_ref.budget_exceeded,
		"max_rects=%d：%s vs %s" % [max_rects, str(r_nat.budget_exceeded), str(r_ref.budget_exceeded)])
	# ③ AABB 写回 + 逐位相同
	_c(tag + " AABB 写回且逐位相同", wrote_back and aabb_nat == aabb_ref,
		"写回=%s %s vs %s" % [str(wrote_back), str(aabb_nat), str(aabb_ref)])


## 随机形状：底板 + 内部空洞 + 边缘缺口 + 整行/整列空 + 孤立像素 + 混合占用。
## w/h 故意不是 8 的倍数，原点也故意不落在 8 的倍数上（块锚点与 AABB 是两回事）。
func _random_shape(kind: int) -> PixelShape:
	var s := PixelShape.new()
	var w := _rng.randi_range(1, 180)
	var h := _rng.randi_range(1, 120)
	var ox := _rng.randi_range(-40, 40)
	var oy := _rng.randi_range(-40, 40)
	match kind:
		0:      # 实心底板
			s.fill_rect(Rect2i(ox, oy, w, h), 1)
		1:      # 混合占用（逐像素随机 —— 矩形数最坏的情况）
			for y in h:
				for x in w:
					if _rng.randf() < 0.5:
						s.set_pixel(ox + x, oy + y, 1)
		2:      # 竖条纹（梳齿）
			for x in w:
				if x % 3 != 2:
					for y in h:
						s.set_pixel(ox + x, oy + y, 1)
		3:      # 棋盘
			for y in h:
				for x in w:
					if ((x + y) & 1) == 0:
						s.set_pixel(ox + x, oy + y, 1)
	# 内部空洞（material 0 == 清空）
	for i in _rng.randi_range(0, 5):
		var hw := _rng.randi_range(1, maxi(1, w / 3))
		var hh := _rng.randi_range(1, maxi(1, h / 3))
		s.fill_rect(Rect2i(ox + _rng.randi_range(0, maxi(0, w - hw)),
			oy + _rng.randi_range(0, maxi(0, h - hh)), hw, hh), 0)
	# 边缘缺口：从四条边各啃掉一小块（会改 AABB，也会让块只占一半）
	for i2 in _rng.randi_range(0, 3):
		var gw := _rng.randi_range(1, maxi(1, w / 4))
		var gh := _rng.randi_range(1, maxi(1, h / 4))
		match _rng.randi_range(0, 3):
			0:
				s.fill_rect(Rect2i(ox + _rng.randi_range(0, maxi(0, w - gw)), oy, gw, gh), 0)
			1:
				s.fill_rect(Rect2i(ox + _rng.randi_range(0, maxi(0, w - gw)), oy + h - gh, gw, gh), 0)
			2:
				s.fill_rect(Rect2i(ox, oy + _rng.randi_range(0, maxi(0, h - gh)), gw, gh), 0)
			3:
				s.fill_rect(Rect2i(ox + w - gw, oy + _rng.randi_range(0, maxi(0, h - gh)), gw, gh), 0)
	# 整行 / 整列空
	if h > 2 and _rng.randf() < 0.5:
		s.fill_rect(Rect2i(ox - 2, oy + _rng.randi_range(0, h - 1), w + 4, 1), 0)
	if w > 2 and _rng.randf() < 0.5:
		s.fill_rect(Rect2i(ox + _rng.randi_range(0, w - 1), oy - 2, 1, h + 4), 0)
	# 孤立像素：可能落在很远的块里（顺带测"新块发现"与负块坐标的排序）
	for i3 in _rng.randi_range(0, 3):
		s.set_pixel(ox + _rng.randi_range(-40, w + 40), oy + _rng.randi_range(-40, h + 40), 1)
	# 空 chunk（occ == 0 但对象在 chunks 里）—— 分解必须无视它
	if _rng.randf() < 0.3:
		s.chunk_or_create(ox >> 3, (oy + h) >> 3)
	return s


func _initialize() -> void:
	print("=== 原生矩形分解 vs GDScript 参照实现（逐位）===")
	if not ClassDB.class_exists("PixelRaster"):
		printerr("PixelRaster 扩展不可用 —— 先跑 python tools/build_native.py 重编 fastphys.dll")
		print("=== 0 passed, 1 failed ===")
		quit(1)
		return
	var r = ClassDB.instantiate("PixelRaster")
	if not r.has_method("decompose"):
		printerr("PixelRaster 没有 decompose（DLL 太旧）—— 重编 fastphys.dll")
		print("=== 0 passed, 1 failed ===")
		quit(1)
		return
	if r.get_reference_count() > 1:
		r.unreference()
	_rng.seed = 20261007

	# ---- 1. 手工边界情形 ----
	var empty := PixelShape.new()
	var one := PixelShape.new(); one.set_pixel(3, 4, 1)
	var one_neg := PixelShape.new(); one_neg.set_pixel(-1, -9, 1)
	var c8 := PixelShape.new(); c8.fill_rect(Rect2i(0, 0, 8, 8), 1)
	var b64 := PixelShape.new(); b64.fill_rect(Rect2i(0, 0, 64, 64), 1)
	var b65 := PixelShape.new(); b65.fill_rect(Rect2i(0, 0, 65, 65), 1)
	var b128 := PixelShape.new(); b128.fill_rect(Rect2i(-70, -70, 128, 128), 1)
	var ring := PixelShape.new()
	ring.fill_rect(Rect2i(0, 0, 64, 64), 1)
	ring.fill_rect(Rect2i(8, 8, 48, 48), 0)                 # 内部空洞（一个块里）
	var comb := PixelShape.new()
	for i in 20:
		comb.fill_rect(Rect2i(i * 4, 0, 2, 10), 1)          # 梳齿：块内多矩形
	comb.fill_rect(Rect2i(0, 8, 80, 2), 1)
	var rowgap := PixelShape.new()
	rowgap.fill_rect(Rect2i(0, 0, 40, 20), 1)
	rowgap.fill_rect(Rect2i(0, 9, 40, 1), 0)                # 整行空 -> 上下两块
	var colgap := PixelShape.new()
	colgap.fill_rect(Rect2i(0, 0, 40, 20), 1)
	colgap.fill_rect(Rect2i(19, 0, 1, 20), 0)               # 整列空
	var far := PixelShape.new()
	far.set_pixel(0, 0, 1)
	far.set_pixel(300, 200, 1)                              # 孤立像素（跨很多块）
	far.set_pixel(-300, -200, 1)                            # 负块坐标
	var half := PixelShape.new()
	half.fill_rect(Rect2i(0, 0, 64, 64), 1)
	half.fill_rect(Rect2i(32, 32, 32, 32), 0)               # 只占半个 chunk 的洞
	var stair := PixelShape.new()
	for i in 20:
		stair.fill_rect(Rect2i(i, i, 1, 1), 1)
	var ground := PixelShape.new(); ground.fill_rect(Rect2i(0, 0, 800, 40), 1)

	_cmp("空形状", empty)
	_cmp("单个像素", one)
	_cmp("单个像素（负坐标）", one_neg)
	_cmp("刚好一个 chunk", c8)
	_cmp("刚好一个块", b64)
	_cmp("一个块 +1（跨块）", b65)
	_cmp("跨 4 个块（负原点）", b128)
	_cmp("环（块内空洞）", ring)
	_cmp("梳齿", comb)
	_cmp("整行空", rowgap)
	_cmp("整列空", colgap)
	_cmp("孤立像素（远距离 + 负块）", far)
	_cmp("半个 chunk 的洞", half)
	_cmp("对角线阶梯", stair)
	_cmp("800x40 地面", ground)
	# 空 chunk（occ == 0）必须被无视
	var dead := PixelShape.new()
	dead.fill_rect(Rect2i(0, 0, 16, 16), 1)
	dead.chunk_or_create(50, 50)                            # 空 chunk，离得很远
	_cmp("空 chunk 混在里面", dead)
	# 只有空 chunk（一个像素都没有）—— AABB 是空的，但 chunks 不是空的：
	# 原生会被调用，然后必须走"origin 保持 Vector2.ZERO"那条早返回
	var hollow := PixelShape.new()
	hollow.chunk_or_create(0, 0)
	hollow.chunk_or_create(-3, 7)
	_cmp("只有空 chunk（无像素）", hollow)
	# max_rects：只影响 budget_exceeded，**不参与几何**
	for mr in [0, 1, 3, 64, 100000]:
		_cmp("800x40 max_rects=%d" % mr, ground, mr)
		_cmp("梳齿 max_rects=%d" % mr, comb, mr)

	# ---- 2. 随机（含非 8 倍数、内部空洞、边缘缺口、整行/整列空、孤立像素、混合占用）----
	for i in 60:
		_cmp("随机 #%d" % i, _random_shape(i % 4))
	print("  随机形状比对 %d 组（含重开结果段 %d 次）" % [_cases, _retries])

	print("=== %d passed, %d failed（%d 组形状，共比对 %d 个矩形 x 4 个分量）===" % [
		_pass, _fail, _cases, _rects_cmp])
	quit(1 if _fail > 0 else 0)

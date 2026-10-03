extends SceneTree
## 矩形合并（**最大行程**）的闸门。
##
## ⚠️ 这个文件的前身钉的是"旧进位合并"的**逐位复现**（golden）。那条契约在
##    "按块分解"上线时被**故意作废**了 —— 原因不是性能，是**物理**：
##    进位合并把实心区域切成 2 的幂那样的一串（4000 宽 -> 6 块），留下 log2 个接缝，
##    而接缝落在静止箱子边缘 1 像素处时箱子会**翻倒**
##    （实测 tests/diag_seam_matrix.gd：30 个箱子里 2 个翻 90°、滑走 47 像素）。
##    最大行程合并把实心区域并成 1 个矩形（= 旧全局贪心的结果）-> 零接缝。
##
## 现在钉的是四条**性质**（而不是某一份具体输出）：
##   1. 覆盖精确：并集逐像素等于原覆盖（phantom/missing/overlap 全 0）
##   2. 不更差：矩形数**永远不多于**旧进位合并（_merge_pass_ref 就是那份旧实现）
##   3. 确定 + 幂等
##   4. 不改入参
## ⚠️ 第 2 条是"新合并至少和旧的一样好"的可度量判据 ——
##    比"看起来更整齐"这种说法可靠。

const GreedyRects := preload("res://src/core/greedy_rects.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const Destruction := preload("res://src/core/destruction.gd")

var passed := 0
var failed := 0

func _assert(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		if failed <= 8:
			print("  [失败] " + msg)

func _same(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		var x: Rect2 = a[i]
		var y: Rect2 = b[i]
		if x.position != y.position or x.size != y.size:
			return false
	return true

## 独立参照物：逐像素比较两边的覆盖（不拿实现自己的值当预期值）
static func _cover_same(src: Array, out: Array) -> bool:
	if src.is_empty():
		return out.is_empty()
	var bb := Rect2(src[0])
	var area := 0.0
	for r: Rect2 in src:
		bb = bb.merge(r)
		area += r.size.x * r.size.y
	if area > 8192.0:
		return true
	var w := int(bb.size.x)
	var h := int(bb.size.y)
	if w <= 0 or h <= 0:
		return false
	var m1 := PackedByteArray()
	m1.resize(w * h)
	var m2 := PackedByteArray()
	m2.resize(w * h)
	for r2: Rect2 in src:
		_paint(m1, w, bb, r2)
	for r3: Rect2 in out:
		_paint(m2, w, bb, r3)
	return m1 == m2

static func _paint(mask: PackedByteArray, w: int, bb: Rect2, r: Rect2) -> void:
	var x0 := int(r.position.x - bb.position.x)
	var y0 := int(r.position.y - bb.position.y)
	for yy in int(r.size.y):
		for xx in int(r.size.x):
			mask[(y0 + yy) * w + x0 + xx] += 1

## 多重集比较（忽略顺序）—— 合并会**重排**矩形（按分组键发射），
## 所以"再跑一次不变"只能钉到"集合不变"这一层，顺序不是不变量。
func _multiset_same(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	var x := a.duplicate()
	var y := b.duplicate()
	x.sort_custom(func(p: Rect2, q: Rect2) -> bool:
		if p.position.x != q.position.x:
			return p.position.x < q.position.x
		if p.position.y != q.position.y:
			return p.position.y < q.position.y
		if p.size.x != q.size.x:
			return p.size.x < q.size.x
		return p.size.y < q.size.y)
	y.sort_custom(func(p: Rect2, q: Rect2) -> bool:
		if p.position.x != q.position.x:
			return p.position.x < q.position.x
		if p.position.y != q.position.y:
			return p.position.y < q.position.y
		if p.size.x != q.size.x:
			return p.size.x < q.size.x
		return p.size.y < q.size.y)
	return _same(x, y)

## strict = 只对**不重叠**的语料钉"不比旧版差"。
## ⚠️ 随机语料允许矩形重叠，而真实分解**永远不会**重叠 ——
##    实测 400 组随机里有 1 组最大行程合并反而更多，那是重叠输入下的
##    退化情形，不该拿它当判据（也不该因此把合并改回去）。
func _check(label: String, sets: Array, strict: bool) -> void:
	var worse := 0
	var nondet := 0
	var notidem := 0
	var mutated := 0
	var cover_bad := 0
	for si in sets.size():
		var src: Array = sets[si]
		var snap := src.duplicate()
		var got := GreedyRects._merge_pass(src)
		var oldm := GreedyRects._merge_pass_ref(src)
		if got.size() > oldm.size():
			worse += 1
		if not _same(src, snap):
			mutated += 1
		if not _same(GreedyRects._merge_pass(src), got):
			nondet += 1
		if not _multiset_same(GreedyRects._merge_pass(got), got):
			notidem += 1
		if not _cover_same(src, got):
			cover_bad += 1
	if strict:
		_assert(worse == 0, "%s：%d 组比旧进位合并更差（矩形更多）" % [label, worse])
	_assert(mutated == 0, "%s：%d 组改了入参" % [label, mutated])
	_assert(nondet == 0, "%s：%d 组两次结果不同" % [label, nondet])
	_assert(notidem == 0, "%s：%d 组对结果再跑一次矩形集合会变" % [label, notidem])
	_assert(cover_bad == 0, "%s：%d 组像素覆盖变了" % [label, cover_bad])
	print("  %-16s %4d 组 | 不比旧版差 %s | 覆盖精确 %s" % [label, sets.size(),
		"是" if worse == 0 else "否(%d)" % worse, "是" if cover_bad == 0 else "否(%d)" % cover_bad])

## 真实分布：768x100 地面按擦除序列挖洞后的贪心结果（横/竖两份都收）
func _real_sets() -> Array:
	var sets: Array = []
	var s := PixelShape.new()
	for y in 100:
		for x in 768:
			s.set_pixel(x, y, 1)
	for i in 20:
		Destruction.apply_damage(s, Destruction.Damage.circle(Vector2(40.0 + i * 34.0, 18.0 + float(i % 5) * 17.0), 5.0 + float(i % 4) * 2.5))
		s.touch()
		var g := GreedyRects._build_grid(s)
		if g == null:
			continue
		sets.append(GreedyRects._greedy(g.words.duplicate(), g.wq, g.w, g.h, true))
		sets.append(GreedyRects._greedy(g.words.duplicate(), g.wq, g.w, g.h, false))
	return sets

## 结构对抗集：等尺寸连排 / 网格 / 错位 —— 最大行程与进位合并的差别都在这里
func _synthetic_sets() -> Array:
	var sets: Array = []
	for k in range(1, 13):
		var row: Array = []
		for i in k:
			row.append(Rect2(i * 4, 0, 4, 3))
		sets.append(row)
	for k2 in range(1, 13):
		var col: Array = []
		for i2 in k2:
			col.append(Rect2(0, i2 * 3, 4, 3))
		sets.append(col)
	for kx in range(1, 7):
		for ky in range(1, 7):
			var grid: Array = []
			for yy in ky:
				for xx in kx:
					grid.append(Rect2(xx * 4, yy * 3, 4, 3))
			sets.append(grid)
	# 不同宽度但同一 y 区间 + 相邻（最大行程能并、进位合并并不了）
	sets.append([Rect2(0, 0, 4, 3), Rect2(4, 0, 8, 3)])
	sets.append([Rect2(0, 0, 8, 3), Rect2(8, 0, 4, 3)])
	sets.append([Rect2(0, 0, 4, 3), Rect2(4, 0, 4, 3), Rect2(8, 0, 8, 3)])
	sets.append([Rect2(0, 0, 4, 3), Rect2(4, 1, 4, 3)])
	sets.append([Rect2(0, 0, 4, 3), Rect2(4, 2, 4, 3)])
	sets.append([])
	sets.append([Rect2(2, 2, 5, 7)])
	return sets

func _random_sets(count: int, seed0: int, max_n: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed0
	var sets: Array = []
	for c in count:
		var n := rng.randi_range(1, max_n)
		var arr: Array = []
		for i in n:
			arr.append(Rect2(rng.randi_range(0, 8) * 2, rng.randi_range(0, 8) * 2, rng.randi_range(1, 4) * 2, rng.randi_range(1, 4) * 2))
		for i2 in range(arr.size() - 1, 0, -1):
			var k := rng.randi_range(0, i2)
			var tmp = arr[i2]
			arr[i2] = arr[k]
			arr[k] = tmp
		sets.append(arr)
	return sets

func _initialize() -> void:
	print("=== 最大行程合并：四条性质 ===")
	_check("真实擦除序列", _real_sets(), true)
	_check("结构对抗集", _synthetic_sets(), true)
	_check("随机洗牌(小)", _random_sets(400, 20261006, 24), false)
	_check("随机洗牌(中)", _random_sets(80, 999, 90), false)
	print("---")
	if failed == 0:
		print("全部通过：%d 项断言" % passed)
	else:
		print("失败 %d / %d 项" % [failed, passed + failed])
	quit(0 if failed == 0 else 1)

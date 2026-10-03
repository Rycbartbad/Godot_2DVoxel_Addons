extends SceneTree
## _merge_pass 等价性闸门：快速版必须与**冻结的旧实现**逐位相同（含顺序）。
##
## 为什么需要它：矩形集合就是 Rapier 的碰撞形状集合，而"集合变了"是**不报错**的 ——
## 只会让形状与碰撞箱静默错位（用户报过两次）。8 条基准在这里是弱证据：
## 基准里的形状几乎都是整块矩形，根本走不到合并。
##
## 三层证据，缺一不可：
##   1. 差分：新实现 vs 冻结旧实现（golden），逐位比矩形**和顺序**
##   2. 独立参照物：按**像素**重建覆盖，确认合并前后覆盖逐格相同
##      （不拿实现自己的值当预期值 —— 会误报的闸门比没有闸门更糟）
##   3. 契约：实现不许改调用方的数组

const GreedyRects := preload("res://src/core/greedy_rects.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const Destruction := preload("res://src/core/destruction.gd")

var passed := 0
var failed := 0

# ==================== golden：旧实现，原样冻结 ====================
## ⚠️⚠️ 这个函数**永远不要改**。它的全部价值就是"它逐位等于 ea72019 时的旧行为"。
##    改它 = 承认矩形集合变了 = 必须单独一个提交 + 重测 8 条基准。
static func golden(rects: Array) -> Array:
	var changed := true
	while changed:
		changed = false
		var out: Array = []
		var used := []
		used.resize(rects.size())
		used.fill(false)
		for i in rects.size():
			if used[i]:
				continue
			var a: Rect2 = rects[i]
			for j in range(i + 1, rects.size()):
				if used[j]:
					continue
				var b: Rect2 = rects[j]
				if a.size == b.size and a.position.y == b.position.y and absf(a.end.x - b.position.x) < 0.001:
					a = Rect2(a.position, Vector2(a.size.x + b.size.x, a.size.y))
					used[j] = true
					changed = true
				elif a.size == b.size and a.position.x == b.position.x and absf(a.end.y - b.position.y) < 0.001:
					a = Rect2(a.position, Vector2(a.size.x, a.size.y + b.size.y))
					used[j] = true
					changed = true
			used[i] = true
			out.append(a)
		rects = out
	return rects

# ==================== 语料 ====================
## 真实分布：768x100 地面按擦除序列挖洞后的贪心结果（横优先 / 竖优先两份都收）
func _real_sets() -> Array:
	var sets: Array = []
	var s := PixelShape.new()
	for y in 100:
		for x in 768:
			s.set_pixel(x, y, 1)
	for i in 34:
		var d := Destruction.Damage.circle(Vector2(40.0 + i * 22.0, 18.0 + float(i % 5) * 17.0), 5.0 + float(i % 4) * 2.5)
		Destruction.apply_damage(s, d)
		s.touch()
		var g := GreedyRects._build_grid(s)
		if g == null:
			continue
		sets.append(GreedyRects._greedy(g.words.duplicate(), g.wq, g.w, g.h, true))
		sets.append(GreedyRects._greedy(g.words.duplicate(), g.wq, g.w, g.h, false))
	return sets

## 结构对抗集：专打旧实现的**顺序语义**（扫过不回头 / 反复跑到不动点）
func _synthetic_sets() -> Array:
	var sets: Array = []
	# 连排：3 个会停在 2 个、4 个才并成 1 个 —— 这一条最容易被"顺手改好"
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
	# 等尺寸网格：要跑好几轮才收敛
	for kx in range(1, 7):
		for ky in range(1, 7):
			var grid: Array = []
			for yy in ky:
				for xx in kx:
					grid.append(Rect2(xx * 4, yy * 3, 4, 3))
			sets.append(grid)
	sets.append([Rect2(0, 0, 4, 3), Rect2(4, 1, 4, 3)])            # 同尺寸但错位
	sets.append([Rect2(0, 0, 4, 3), Rect2(4, 0, 8, 3)])            # 共享整边但跨度不同
	sets.append([Rect2(0, 0, 4, 3), Rect2(4, 2, 4, 3)])            # 相邻但 y 不同
	sets.append([Rect2(0, 0, 4, 3), Rect2(0, 3, 4, 6), Rect2(4, 0, 4, 3)])
	sets.append([Rect2(0, 0, 4, 3), Rect2(4, 0, 4, 3), Rect2(0, 3, 4, 3), Rect2(4, 3, 4, 3)])
	sets.append([Rect2(0, 0, 4, 3), Rect2(4, 0, 4, 3), Rect2(8, 0, 4, 3), Rect2(0, 3, 12, 3)])
	sets.append([])
	sets.append([Rect2(2, 2, 5, 7)])
	sets.append([Rect2(2, 2, 5, 7), Rect2(7, 2, 5, 7), Rect2(12, 2, 5, 7)])
	return sets

## 非整数坐标：新实现必须整段退回旧实现（0.001 容差是精确键复现不了的）
func _fractional_sets() -> Array:
	return [
		[Rect2(0.0, 0.0, 4.0, 3.0), Rect2(4.0005, 0.0, 4.0, 3.0)],
		[Rect2(0.5, 0.0, 4.0, 3.0), Rect2(4.5, 0.0, 4.0, 3.0), Rect2(8.5, 0.0, 4.0, 3.0)],
		[Rect2(-0.25, 1.5, 2.0, 2.0), Rect2(1.75, 1.5, 2.0, 2.0)],
	]

func _random_sets(count: int, seed0: int, max_n: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed0
	var sets: Array = []
	for c in count:
		var n := rng.randi_range(1, max_n)
		var arr: Array = []
		for i in n:
			var w := rng.randi_range(1, 4) * 2
			var h := rng.randi_range(1, 4) * 2
			var x := rng.randi_range(0, 8) * 2
			var y := rng.randi_range(0, 8) * 2
			arr.append(Rect2(x, y, w, h))
		# 旧实现的结果**依赖顺序** —— 顺序是必须覆盖的一维，所以自己洗牌（固定种子，可复现）
		for i2 in range(arr.size() - 1, 0, -1):
			var k := rng.randi_range(0, i2)
			var tmp = arr[i2]
			arr[i2] = arr[k]
			arr[k] = tmp
		sets.append(arr)
	return sets

# ==================== 工具 ====================
static func _same(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		var x: Rect2 = a[i]
		var y: Rect2 = b[i]
		if x.position != y.position or x.size != y.size:
			return false
	return true

## 独立参照物：按**像素**重建两边的覆盖，逐格比。
## 面积太大就跳过（真实语料是 768x100，逐格扫不值当）。
static func _cover_mismatch(src: Array, out: Array) -> String:
	if src.is_empty():
		return "" if out.is_empty() else "空输入却有输出"
	var bb := Rect2(src[0])
	var area := 0.0
	for r: Rect2 in src:
		bb = bb.merge(r)
		area += r.size.x * r.size.y
	if area > 4096.0:
		return ""
	var w := int(bb.size.x)
	var h := int(bb.size.y)
	if w <= 0 or h <= 0:
		return "退化包围盒"
	var m1 := PackedByteArray()
	m1.resize(w * h)
	var m2 := PackedByteArray()
	m2.resize(w * h)
	for r2: Rect2 in src:
		_paint(m1, w, bb, r2)
	for r3: Rect2 in out:
		_paint(m2, w, bb, r3)
	if m1 != m2:
		for i in w * h:
			if m1[i] != m2[i]:
				return "像素覆盖不一致 @%d src=%d out=%d" % [i, m1[i], m2[i]]
	return ""

static func _paint(mask: PackedByteArray, w: int, bb: Rect2, r: Rect2) -> void:
	var x0 := int(r.position.x - bb.position.x)
	var y0 := int(r.position.y - bb.position.y)
	for yy in int(r.size.y):
		for xx in int(r.size.x):
			mask[(y0 + yy) * w + x0 + xx] += 1

func _check(label: String, sets: Array, oracle: bool, ref_too: bool) -> void:
	var n_diff := 0
	var n_cover := 0
	var n_immut := 0
	for si in sets.size():
		var src: Array = sets[si]
		var snap := src.duplicate()
		var g := golden(src)
		var got := GreedyRects._merge_pass(src)
		# 逐组断言（不是每组一句"全部一致"）：这样汇总行里的数字就是**真的比过多少组**
		var ok := _same(got, g)
		if not ok:
			n_diff += 1
			if n_diff <= 2:
				print("  [差异] %s #%d n=%d\n    golden %s\n    实际   %s" % [label, si, src.size(), str(g), str(got)])
		_assert(ok, "%s #%d：与 golden 不一致" % [label, si])
		var immut := _same(src, snap)
		if not immut:
			n_immut += 1
		_assert(immut, "%s #%d：改动了调用方的数组" % [label, si])
		if ref_too:
			_assert(_same(GreedyRects._merge_pass_ref(src), g), "%s #%d：兜底实现与 golden 不一致" % [label, si])
		if oracle:
			var msg := _cover_mismatch(src, got)
			n_cover += 1
			if msg != "":
				n_diff += 1
				print("  [覆盖] %s #%d %s" % [label, si, msg])
			_assert(msg == "", "%s #%d：%s" % [label, si, msg])
	print("  %-14s %4d 组 | 与 golden 一致 %s | 未改入参 %s | 覆盖对拍 %d 组 %s" % [
		label, sets.size(),
		"是" if n_diff == 0 else "否(%d)" % n_diff,
		"是" if n_immut == 0 else "否(%d)" % n_immut,
		n_cover, "全部一致" if n_diff == 0 else "有差异"])

## 逐项计数、默认不打印（细节由 _check 的汇总行负责）——
## 汇总行里的数字必须是"真的比过多少组"，不能是恒真的自证。
func _assert(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		if failed <= 8:
			print("  [失败] " + msg)

func _initialize() -> void:
	print("=== _merge_pass 等价性（快速版 vs 冻结旧实现）===")
	_check("真实擦除序列", _real_sets(), false, false)
	_check("结构对抗集", _synthetic_sets(), true, false)
	_check("随机洗牌(小)", _random_sets(400, 20261003, 24), true, false)
	_check("随机洗牌(中)", _random_sets(60, 777, 90), false, false)
	# 非整数：走兜底那一支。这里测的是**判据**与**兜底实现**各自正确 ——
	# 兜底按定义就等于 golden，所以"新实现真的走了那一支"是测不出来的，
	# 能测的是 _is_int_rect 判得对、且 _merge_pass_ref 逐位等于历史行为。
	var frac := _fractional_sets()
	_check("非整数(兜底)", frac, false, true)
	var ints_ok := GreedyRects._is_int_rect(Rect2(1, 2, 3, 4)) and not GreedyRects._is_int_rect(Rect2(1.5, 2, 3, 4)) \
		and not GreedyRects._is_int_rect(Rect2(-0.25, 0, 1, 1)) and GreedyRects._is_int_rect(Rect2(-4, -5, 6, 7))
	_assert(ints_ok, "_is_int_rect 判据不对：整数矩形被拒或小数矩形被收")

	print("---")
	if failed == 0:
		print("全部通过：%d 项断言" % passed)
	else:
		print("失败 %d / %d 项" % [failed, passed + failed])
	quit(0 if failed == 0 else 1)

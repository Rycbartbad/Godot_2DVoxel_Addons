extends RefCounted
## 像素团 -> 局部空间矩形集合（贪心最大矩形分解）。
##
## 为什么不用凸包：
##   2D 像素物体大量是凹的（L 形墙、楼梯、手绘的不规则形状）。
##   凸包会把凹角"填平"，产生看不见的碰撞体积。
##   贪心矩形分解是像素的**精确覆盖**：面积和 == 像素数，互不重叠，无幻影格。
##
## 关于预算（重要）：
##   精确覆盖与"矩形数量上限"在一般情况下是**不可兼得**的。
##   用包围盒去兜底会产生大量幻影碰撞体（实测一个 2400 像素的梳齿形
##   会凭空多出 1600 个碰撞格），所以这里的策略是：
##     - decompose()        永远精确。max_rects 只是"超了要告诉我"的阈值。
##     - decompose_proxy()  显式选择的近似代理，调用方自己承担幻影体积。

const Bits := preload("res://src/core/pixel_bits.gd")
const PixelChunk := preload("res://src/core/pixel_chunk.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

class Grid:
	var cells: PackedByteArray = PackedByteArray()
	var w := 0
	var h := 0
	var origin := Vector2i.ZERO


class Result:
	var rects: Array = []            # Array[Rect2]，Shape 局部像素空间
	var origin: Vector2 = Vector2.ZERO
	var budget_exceeded := false
	var exact := true

	func rect_count() -> int:
		return rects.size()

	func covered_area() -> float:
		var a := 0.0
		for r: Rect2 in rects:
			a += r.size.x * r.size.y
		return a


static func decompose(shape: PixelShape, max_rects: int = 0) -> Result:
	var res := Result.new()
	var g := _build_grid(shape)
	if g == null:
		return res

	# 双向贪心：横优先 / 竖优先各跑一遍，取矩形更少的那份（两者都精确）
	#
	# ⚠️ 第一遍就是 1 个矩形的话，**第二遍不可能更好**（1 已经是最少），
	#    直接跳过 —— 精确、通用，不是特例优化。
	#
	#    实心地面（768x100）走的正是这条：第一遍立刻得到覆盖全形状的 1 个矩形，
	#    省掉第二遍的 76800 格扫描 + 76800 格清零。
	#    实测 decompose 42.36 -> 20.58 ms 是靠原生 find()，
	#    这一条再砍掉其中一半。
	var a := _greedy(g.cells.duplicate(), g.w, g.h, true)
	var rects: Array = a
	if a.size() > 1:
		var b := _greedy(g.cells.duplicate(), g.w, g.h, false)
		if b.size() < a.size():
			rects = b
	rects = _merge_pass(rects)

	var offset := Vector2(g.origin)
	for i in rects.size():
		var r: Rect2 = rects[i]
		rects[i] = Rect2(r.position + offset, r.size)
	res.origin = offset
	res.rects = rects
	if max_rects > 0 and rects.size() > max_rects:
		res.budget_exceeded = true
	return res


## 显式选择的近似代理：矩形数被压到 max_rects 以内，但会引入幻影碰撞体积。
## 只有在"这个物体离玩家很远 / 只是背景装饰"时才应该用它。
static func decompose_proxy(shape: PixelShape, max_rects: int) -> Result:
	var res := decompose(shape, 0)
	if max_rects <= 0 or res.rects.size() <= max_rects:
		return res
	var sorted := res.rects.duplicate()
	sorted.sort_custom(func(x: Rect2, y: Rect2) -> bool:
		return x.size.x * x.size.y > y.size.x * y.size.y)
	var out: Array = []
	for i in mini(max_rects - 1, sorted.size()):
		out.append(sorted[i])
	var rest := Rect2(sorted[max_rects - 1].position, sorted[max_rects - 1].size)
	for i in range(max_rects - 1, sorted.size()):
		rest = rest.merge(sorted[i])
	out.append(rest)
	res.rects = out
	res.exact = false
	res.budget_exceeded = true
	return res


## 把 Shape 铺成 w*h 的 0/1 网格。空形状返回 null。
static func _build_grid(shape: PixelShape) -> Grid:
	var aabb := shape.local_aabb()
	if aabb.size.x <= 0 or aabb.size.y <= 0:
		return null
	var g := Grid.new()
	g.w = aabb.size.x
	g.h = aabb.size.y
	g.origin = aabb.position
	var w := g.w
	var h := g.h
	var grid := PackedByteArray()
	grid.resize(w * h)
	grid.fill(0)
	# ⚠️⚠️ **实心快路径**：整个外接盒都被占满时，直接 fill(1)（原生 memset）。
	#
	#    下面那个逐 chunk 逐像素的循环，对 768x100 的实心地面是
	#    1248 chunk x 8 行 x 8 次赋值 = **79872 次 GDScript 写**，
	#    实测 **8.71 ms** —— 而整个 decompose 只有 10.57 ms。
	#
	#    我前几轮一直在优化 _greedy（find / 跳过第二遍），那是 1.76 ms 的小头，
	#    所以"大物体的擦除优化没起作用"—— **打错了目标**。
	#    物体越大这个循环越长，正是用户说的"特别是大物体"。
	#
	#    判据是精确的：占满外接盒 <=> pixel_count == w*h。
	#    实心地面、实心箱子、未破坏的大地形都走这条。
	if shape.pixel_count() == w * h:
		grid.fill(1)
		g.cells = grid
		return g
	# ⚠️ 试过把这里改成"逐行用 append_array/slice 原生拼接"（配 256 项
	#    8 字节模式表）—— **实测同样是 8.71 ms，白做**，已回退。
	#
	#    原因：地板不在"每次写多少字节"，而在**迭代次数** ——
	#    768x100 是 96 chunk x 100 行 = 9600 次 chunk-行访问，
	#    无论里面是 8 次赋值还是 1 次原生拼接，都要付这 9600 次的代价。
	#
	#    要真正降下来只能**减少迭代**（比如用位网格：1248 个 word 而不是
	#    76800 个字节），那是重写 _greedy，不是改这一处能解决的。
	#
	#    真正有效的是上面的**实心快路径**（fill(1)，8.71 -> 0.52 ms）。
	for k: int in shape.chunks:
		var c: PixelChunk = shape.chunks[k]
		var bx := (PixelShape.key_x(k) << 3) - aabb.position.x
		var by := (PixelShape.key_y(k) << 3) - aabb.position.y
		for y in 8:
			var gy := by + y
			if gy < 0 or gy >= h:
				continue
			var row := Bits.row_bits(c.occ, y)
			if row == 0:
				continue
			for x in 8:
				if ((row >> x) & 1) == 0:
					continue
				var gx := bx + x
				if gx >= 0 and gx < w:
					grid[gy * w + gx] = 1
	g.cells = grid
	return g


## 贪心最大矩形。horizontal_first 决定先向右还是先向下扩，
## 两种顺序都是精确覆盖，但矩形数量可能不同。
static func _greedy(grid: PackedByteArray, w: int, h: int, horizontal_first: bool) -> Array:
	var rects: Array = []
	# ⚠️⚠️ 用 PackedByteArray.find()（**原生 memchr**）找下一个占用格，
	#    不要写 GDScript 的双重循环逐格扫。
	#
	#    原来写的是 for y in h: for x in w: if grid[...] == 0: continue ——
	#    768x100 的地面每遍要跑 **76800 次 GDScript 迭代**，而 decompose 跑两遍，
	#    实测就是 **42 ms/笔**（擦除路径上最大的一块）。
	#
	#    find() 在 C++ 里扫，同样的数据只要几十微秒。
	#    这是"把 GDScript 循环换成原生扫描"的典型场景：
	#    算法没变、结果逐字相同，只是把扫描搬进了引擎。
	var cursor := 0
	var n := w * h
	while cursor < n:
		var idx := grid.find(1, cursor)
		if idx < 0:
			break
		var y := idx / w
		var x := idx - y * w
		var base := y * w
		var rw := 1
		var rh := 1
		if horizontal_first:
			while x + rw < w and grid[base + x + rw] != 0:
				rw += 1
			rh = _extend_down(grid, w, h, x, y, rw)
		else:
			while y + rh < h and grid[(y + rh) * w + x] != 0:
				rh += 1
			rw = _extend_right(grid, w, h, x, y, rh)
		# ⚠️ 清零这一步现在是**主要成本**：实心地面一次就是 76800 次 GDScript 赋值。
		#
		#    试过 grid.fill(0, cb, cb+rw) 逐行清零 —— **不行**：
		#    PackedByteArray.fill() 只接受一个参数（没有范围重载），
		#    传三个会让整个 GreedyRects 编译失败，而报错落在**依赖它的脚本**上
		#    （pbody.gd:331），不指向真因。
		#
		#    改成**整行覆盖时整体替换**：slice / resize / append_array 都是原生拷贝。
		#    resize 会把新增的部分**补 0**，正好就是要的效果。
		#    实心地面（1 个全宽矩形）于是从 76800 次赋值变成 4 次原生调用。
		var cb0 := y * w + x
		if rw == w:
			var head := grid.slice(0, cb0)
			head.resize(cb0 + w * rh)
			head.append_array(grid.slice(cb0 + w * rh))
			grid = head
		else:
			for j in rh:
				var cb := (y + j) * w + x
				for i in rw:
					grid[cb + i] = 0
		rects.append(Rect2(x, y, rw, rh))
		cursor = base + x
	return rects


static func _extend_down(grid: PackedByteArray, w: int, h: int, x: int, y: int, rw: int) -> int:
	var rh := 1
	while y + rh < h:
		var rb := (y + rh) * w + x
		var ok := true
		for i in rw:
			if grid[rb + i] == 0:
				ok = false
				break
		if not ok:
			break
		rh += 1
	return rh


static func _extend_right(grid: PackedByteArray, w: int, h: int, x: int, y: int, rh: int) -> int:
	var rw := 1
	while x + rw < w:
		var ok := true
		for j in rh:
			if grid[(y + j) * w + x + rw] == 0:
				ok = false
				break
		if not ok:
			break
		rw += 1
	return rw


## 合并共享整条边且跨度相同的矩形（精确，不会引入幻影）。
static func _merge_pass(rects: Array) -> Array:
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

extends RefCounted
## 一个"形状"= 一组局部 chunk 坐标下的 8x8 像素块。
## 对应 Teardown 的 Shape：体素块，属于某个 Body。
##
## 关键不变量（与 Teardown 官方规则一致）：
##   Shape 内部必须 4 邻域连通，不能有孤岛；出现孤岛时必须拆成多个 Shape。
##   对角接触不算连接。

const Bits := preload("res://src/core/pixel_bits.gd")
const PixelChunk := preload("res://src/core/pixel_chunk.gd")
const Destruction := preload("res://src/core/destruction.gd")

## local chunk 坐标 -> PixelChunk
var chunks: Dictionary = {}

## ---- 脏区域跟踪 ----
##
## 记录"本 tick 哪些 chunk 被写过"。元胞自动机这类逐体素模拟**不能每 tick 扫全部体素**
## （240 个碎片 × 16 像素 = 3840 个体素，全扫必崩），必须只处理变过的地方。
##
## ⚠️ 直接改 chunk.mat / chunk.occ（批量写入，性能需要）时**不会自动标记**，
##    那种路径要自己调 mark_dirty()。逐像素的 set_pixel / set_aux 会自动标记。
var _dirty: Dictionary = {}


## 标记一个 chunk 为脏（chunk 坐标）。已经脏了就早退，热路径上只有一次查表。
func mark_dirty(cx: int, cy: int) -> void:
	var k := make_key(cx, cy)
	if not _dirty.has(k):
		_dirty[k] = true


func mark_dirty_key(k: int) -> void:
	if not _dirty.has(k):
		_dirty[k] = true


## 有没有待处理的脏块。世界层靠它快速跳过干净的形状。
func has_dirty() -> bool:
	return not _dirty.is_empty()


## 本 tick 被写过的 chunk key（PackedInt64Array，可直接拿去遍历）。
func dirty_chunks() -> PackedInt64Array:
	var out := PackedInt64Array()
	out.resize(_dirty.size())
	var i := 0
	for k: int in _dirty:
		out[i] = k
		i += 1
	return out


func clear_dirty() -> void:
	_dirty.clear()


## 读/写逐体素辅助表。引擎不解释语义（见 PixelChunk.aux 的说明）。
func get_aux(x: int, y: int) -> int:
	var cx := x >> 3
	var cy := y >> 3
	var c: PixelChunk = chunks.get(make_key(cx, cy))
	if c == null:
		return 0
	return c.aux[(y - (cy << 3)) * Bits.SIZE + (x - (cx << 3))]


func set_aux(x: int, y: int, v: int) -> void:
	var cx := x >> 3
	var cy := y >> 3
	var c: PixelChunk = chunks.get(make_key(cx, cy))
	if c == null:
		return
	c.aux[(y - (cy << 3)) * Bits.SIZE + (x - (cx << 3))] = v
	mark_dirty(cx, cy)

## 这个 Shape 的密度倍率（Teardown 的 SetShapeDensity / GetShapePalette 那一套）。
## 质量 = Σ(材质密度) * density_scale。默认 1.0，不影响既有行为。
var density_scale := 1.0
## 拥有它的刚体，由 PBody.rebuild 写入（Teardown 的 GetShapeBody）。
## ⚠️ 一个 Shape 只应属于一个刚体；如果同一个 Shape 被塞进两个刚体，
##    这里只会记住最后一个。
var owner_body = null

static func make_key(cx: int, cy: int) -> int:
	return (cx << 32) | (cy & 0xFFFFFFFF)

static func key_x(k: int) -> int:
	return k >> 32

static func key_y(k: int) -> int:
	return (k << 32) >> 32

func is_empty() -> bool:
	return chunks.is_empty()

func chunk_at(cx: int, cy: int) -> PixelChunk:
	return chunks.get(make_key(cx, cy))

func chunk_or_create(cx: int, cy: int) -> PixelChunk:
	var k := make_key(cx, cy)
	var c: PixelChunk = chunks.get(k)
	if c == null:
		c = PixelChunk.new()
		chunks[k] = c
	return c

func set_pixel(x: int, y: int, material: int) -> void:
	## 全局局部像素坐标（可为负）。
	var cx := x >> 3
	var cy := y >> 3
	chunk_or_create(cx, cy).set_pixel(x - (cx << 3), y - (cy << 3), material)
	mark_dirty(cx, cy)

## 只在像素原本为空时写入，返回是否真的新增（画笔需要统计"新增了多少像素"）。
func add_pixel(x: int, y: int, material: int) -> bool:
	var cx := x >> 3
	var cy := y >> 3
	var c := chunk_or_create(cx, cy)
	var lx := x - (cx << 3)
	var ly := y - (cy << 3)
	if (c.occ & Bits.bit(lx, ly)) != 0:
		return false
	c.set_pixel(lx, ly, material)
	mark_dirty(cx, cy)
	return true


func clear_pixel(x: int, y: int) -> void:
	var cx := x >> 3
	var cy := y >> 3
	var c: PixelChunk = chunks.get(make_key(cx, cy))
	if c != null:
		c.clear_pixel(x - (cx << 3), y - (cy << 3))
		mark_dirty(cx, cy)
		if c.is_empty():
			chunks.erase(make_key(cx, cy))

func pixel_count() -> int:
	var n := 0
	for c: PixelChunk in chunks.values():
		n += c.count()
	return n


## 读一个像素的**材质 id**（== 渲染调色板里的下标）。0 表示空。
## 坐标是 Shape 的局部像素坐标（可为负）。
func get_pixel(x: int, y: int) -> int:
	var cx := x >> 3
	var cy := y >> 3
	var c: PixelChunk = chunks.get(make_key(cx, cy))
	if c == null:
		return 0
	return c.get_material(x - (cx << 3), y - (cy << 3))


## 用矩形填一段像素。**material == 0 等价于清空**（与 get_pixel 的 0=空 一致）。
## rect 的右下是开区间，负坐标合法。
func fill_rect(rect: Rect2i, material: int) -> void:
	if rect.size.x <= 0 or rect.size.y <= 0:
		return
	var y1 := rect.position.y + rect.size.y
	var x1 := rect.position.x + rect.size.x
	for y in range(rect.position.y, y1):
		for x in range(rect.position.x, x1):
			if material == 0:
				clear_pixel(x, y)
			else:
				set_pixel(x, y, material)


## 把整个形状的像素**线性平移**（局部空间里的平移，不动刚体）。
## 拖拽编辑、把碎片错位摆放时用得上。
##
## ⚠️ 单位是**像素**，不是 chunk。第一版直接把 dx 加在 chunk 坐标上，
## 结果 translate_pixels(0, -4) 实际位移了 -32（4 x 8）——
## 而且它不会报错，只会让"两个形状该相邻却不相邻"这类判定莫名其妙地失败。
func translate_pixels(dx: int, dy: int) -> void:
	if dx == 0 and dy == 0:
		return
	var out := {}
	for k: int in chunks:
		var c: PixelChunk = chunks[k]
		if c.occ == 0:
			continue
		var bx := key_x(k) << 3
		var by := key_y(k) << 3
		var bits := c.occ
		while bits != 0:
			var i := Bits.first_bit_index(bits)
			bits &= bits - 1
			var px := bx + (i & 7) + dx
			var py := by + (i >> 3) + dy
			var cx := px >> 3
			var cy := py >> 3
			var key := make_key(cx, cy)
			var dst: PixelChunk = out.get(key)
			if dst == null:
				dst = PixelChunk.new()
				out[key] = dst
			dst.set_pixel(px - (cx << 3), py - (cy << 3), c.mat[i])
	chunks = out


## 材质直方图：material id -> 像素数（不含 0）。
## 质量估算、碎片统计、按材质计分都用它。
func count_by_material() -> Dictionary:
	var out := {}
	for c: PixelChunk in chunks.values():
		var m := c.occ
		while m != 0:
			var i := Bits.first_bit_index(m)
			var id := c.mat[i]
			out[id] = int(out.get(id, 0)) + 1
			m &= m - 1
	return out


## 把一种材质整体换成另一种（"烧焦/结冰/腐蚀"这类整块改色）。返回改动的像素数。
func remap_material(from_id: int, to_id: int) -> int:
	var n := 0
	for c: PixelChunk in chunks.values():
		var m := c.occ
		while m != 0:
			var i := Bits.first_bit_index(m)
			if c.mat[i] == from_id:
				c.mat[i] = to_id
				n += 1
			m &= m - 1
	return n

func local_aabb() -> Rect2i:
	## 返回像素级 AABB（左上闭、右下开区间），空形状返回 Rect2i()。
	var min_x := 1 << 30
	var min_y := 1 << 30
	var max_x := -(1 << 30)
	var max_y := -(1 << 30)
	for k: int in chunks:
		var c: PixelChunk = chunks[k]
		if c.occ == 0:
			continue
		var bx := key_x(k) << 3
		var by := key_y(k) << 3
		for y in 8:
			var row := Bits.row_bits(c.occ, y)
			if row == 0:
				continue
			var lo := Bits.first_bit_index(row)
			var hi := 8
			while hi > lo and ((row >> (hi - 1)) & 1) == 0:
				hi -= 1
			min_x = mini(min_x, bx + lo)
			max_x = maxi(max_x, bx + hi)
			min_y = mini(min_y, by + y)
			max_y = maxi(max_y, by + y + 1)
	if max_x <= min_x:
		return Rect2i()
	return Rect2i(min_x, min_y, max_x - min_x, max_y - min_y)

func blit_mask_from(src: PixelChunk, key: int, mask: int) -> void:
	## split 用：把 src 里 mask 内的像素按 key 复制进本 Shape。
	var target := chunk_or_create(key_x(key), key_y(key))
	src.blit_into(target, mask)
	mark_dirty_key(key)


## ---- 体素遍历原语 ----
##
## 引擎负责"怎么走"，**规则由游戏层给**（谓词 + 访问者都是 Callable）。
## 这样"蓝线传信号""绿线生长""红色蔓延"能共用同一套遍历，
## 而引擎完全不知道这些概念。

const OFFSETS_4: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const OFFSETS_8: Array = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]


## 邻域像素坐标。⚠️ 每次调用都会新建数组 ——
## 逐像素的热循环里请直接内联 OFFSETS_4/OFFSETS_8，别调这个。
func neighbors(x: int, y: int, diagonal := false) -> Array:
	var out: Array = []
	for off: Vector2i in (OFFSETS_8 if diagonal else OFFSETS_4):
		out.append(Vector2i(x + off.x, y + off.y))
	return out


## 每像素的**连通分量序号**（-1 = 空）。
##
## 返回 { "count": n, "chunks": { chunk_key: PackedInt32Array(64) } }。
## 一次算好之后，"这个像素属于哪个连通体"就是 O(1) ——
## 比每次重跑一遍连通性判定便宜得多。
##
## 底层走的是 Destruction.components()，也就是 split() 用的**同一份**计算。
func component_map() -> Dictionary:
	var groups := Destruction.components(self)
	var out := {}
	var ci := 0
	for idx in groups:
		var g: Dictionary = groups[idx]
		for k: int in g:
			var arr: PackedInt32Array
			if out.has(k):
				arr = out[k]
			else:
				arr = PackedInt32Array()
				arr.resize(Bits.PIXELS)
				arr.fill(-1)
				out[k] = arr
			var mask: int = g[k]
			while mask != 0:
				var i := Bits.first_bit_index(mask)
				mask &= mask - 1
				arr[i] = ci
		ci += 1
	return {"count": ci, "chunks": out}


## 沿连通体素做 BFS。**谓词和访问者都由游戏层提供** —— 引擎只负责"怎么走"。
##
##   matches(x, y, material, dist) -> bool   能不能踏进这个像素
##   visit(x, y, material, dist) -> bool     访问它；**返回 false 就停止整趟遍历**
##
## 返回访问到的像素数。起点为空、或被 matches 拒绝时返回 0。
##
## 典型用法：
##   蓝线传信号 —— visit 里按 dist 衰减，matches 里限材质
##   绿线生长   —— visit 里改 aux/mat（改完记得 mark_dirty）
##   红色蔓延   —— visit 里收集待爆体素，遍历结束后统一处理
##
## ⚠️ **GDScript 的 lambda 按值捕获局部变量** —— visit 里改一个局部标量
##    （比如 `var count := 0` 然后 count += 1）**不会传出去**。
##    要累积结果请用 Array / Dictionary / 对象成员（引用类型）。
##    实测症状：visit 明明被调用了，外面的计数还是 0。
func flood(from: Vector2i, matches: Callable, visit: Callable, diagonal := false) -> int:
	var m0 := get_pixel(from.x, from.y)
	if m0 == 0:
		return 0
	if matches.is_valid() and not matches.call(from.x, from.y, m0, 0):
		return 0
	var seen := {}
	seen[make_key(from.x, from.y)] = true
	var queue: Array = [from]
	var dists: Array = [0]
	var head := 0
	var count := 0
	var offsets: Array = OFFSETS_8 if diagonal else OFFSETS_4
	while head < queue.size():
		var p: Vector2i = queue[head]
		var d: int = dists[head]
		head += 1
		count += 1
		if visit.is_valid() and not visit.call(p.x, p.y, get_pixel(p.x, p.y), d):
			return count
		for off: Vector2i in offsets:
			var nx := p.x + off.x
			var ny := p.y + off.y
			var k := make_key(nx, ny)
			if seen.has(k):
				continue
			var m := get_pixel(nx, ny)
			if m == 0:
				continue
			if matches.is_valid() and not matches.call(nx, ny, m, d + 1):
				continue
			seen[k] = true
			queue.append(Vector2i(nx, ny))
			dists.append(d + 1)
	return count

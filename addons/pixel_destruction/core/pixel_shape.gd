extends RefCounted
## 一个"形状"= 一组局部 chunk 坐标下的 8x8 像素块。
## 对应 Teardown 的 Shape：体素块，属于某个 Body。
##
## 关键不变量（与 Teardown 官方规则一致）：
##   Shape 内部必须 4 邻域连通，不能有孤岛；出现孤岛时必须拆成多个 Shape。
##   对角接触不算连接。

const Bits := preload("res://addons/pixel_destruction/core/pixel_bits.gd")
const PixelChunk := preload("res://addons/pixel_destruction/core/pixel_chunk.gd")

## local chunk 坐标 -> PixelChunk
var chunks: Dictionary = {}

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
	return true


func clear_pixel(x: int, y: int) -> void:
	var cx := x >> 3
	var cy := y >> 3
	var c: PixelChunk = chunks.get(make_key(cx, cy))
	if c != null:
		c.clear_pixel(x - (cx << 3), y - (cy << 3))
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

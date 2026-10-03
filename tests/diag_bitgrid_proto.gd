extends SceneTree
## 位网格原型 vs 现在的字节网格 —— **先量再改**。
##
## 推演：位网格对"建网格"的改善可能有限（每个 chunk-行仍要一次掩码写，
## 9984 行 x 约 6 ops 约 6 万次 vs 79872 次字节写）；
## 真正的赢面在**清零**（全宽矩形 76800 -> 1200）。
## 不猜，量。
const AddonWorld := preload("res://src/nodes/pixel_world.gd")
const AddonBody := preload("res://src/nodes/pixel_body_2d.gd")
const AddonShape := preload("res://src/nodes/pixel_shape_2d.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const PixelChunk := preload("res://src/core/pixel_chunk.gd")
const Bits := preload("res://src/core/pixel_bits.gd")

# ---------- 现字节版（抄自 greedy_rects._build_grid 全量路径）----------
static func byte_build(s: PixelShape) -> PackedByteArray:
	var aabb: Rect2i = s.local_aabb()
	var w: int = aabb.size.x
	var h: int = aabb.size.y
	var grid := PackedByteArray()
	grid.resize(w * h)
	grid.fill(0)
	for k: int in s.chunks:
		var c: PixelChunk = s.chunks[k]
		var bx: int = (PixelShape.key_x(k) << 3) - aabb.position.x
		var by: int = (PixelShape.key_y(k) << 3) - aabb.position.y
		for y in 8:
			var gy: int = by + y
			if gy < 0 or gy >= h: continue
			var row: int = Bits.row_bits(c.occ, y)
			if row == 0: continue
			for x in 8:
				if ((row >> x) & 1) == 0: continue
				var gx: int = bx + x
				if gx >= 0 and gx < w:
					grid[gy * w + gx] = 1
	return grid

# ---------- 位版原型 ----------
static func write_row_bits(words: PackedInt64Array, wq: int, w: int, bx: int, gy: int, row: int) -> void:
	var start: int = bx
	var bits: int = row
	if start < 0:
		bits = bits >> (-start)
		start = 0
	var end: int = mini(bx + 8, w)
	if end <= start: return
	var count: int = end - start
	var off: int = start & 63
	var wi: int = gy * wq + (start >> 6)
	if off + count <= 64:
		var mask: int = ((1 << count) - 1) << off
		words[wi] = (words[wi] & ~mask) | ((bits << off) & mask)
	else:
		var lo_count: int = 64 - off
		var lo_mask := ((1 << lo_count) - 1) << off
		words[wi] = (words[wi] & ~lo_mask) | ((bits << off) & lo_mask)
		var hi_count: int = count - lo_count
		var hi_mask := (1 << hi_count) - 1
		words[wi + 1] = (words[wi + 1] & ~hi_mask) | ((bits >> lo_count) & hi_mask)

static func bit_build(s: PixelShape) -> PackedInt64Array:
	var aabb: Rect2i = s.local_aabb()
	var w: int = aabb.size.x
	var h: int = aabb.size.y
	var wq: int = (w + 63) >> 6
	var words := PackedInt64Array()
	words.resize(wq * h)
	for k: int in s.chunks:
		var c: PixelChunk = s.chunks[k]
		var bx: int = (PixelShape.key_x(k) << 3) - aabb.position.x
		var by: int = (PixelShape.key_y(k) << 3) - aabb.position.y
		for y in 8:
			var gy: int = by + y
			if gy < 0 or gy >= h: continue
			var row: int = Bits.row_bits(c.occ, y)
			write_row_bits(words, wq, w, bx, gy, row)
	return words

# ---------- 清零对比 ----------
static func byte_clear(grid: PackedByteArray, w: int, h: int) -> PackedByteArray:
	# 现在 _greedy 里的做法：全宽矩形用 slice/resize 整体替换
	var head := grid.slice(0, 0)
	head.resize(w * h)
	return head

static func bit_clear(words: PackedInt64Array, wq: int, w: int, h: int) -> PackedInt64Array:
	# 位版：rh x ceil(rw/64) 次 AND
	var out := words.duplicate()
	var rw := w
	var rh := h
	var x := 0
	var end: int = x + rw
	for j in rh:
		var base := j * wq
		var cx: int = x
		while cx < end:
			var wi: int = base + (cx >> 6)
			var off: int = cx & 63
			var take: int = mini(64 - off, end - cx)
			var mask: int = -1
			if take < 64: mask = ((1 << take) - 1) << off
			out[wi] = out[wi] & ~mask
			cx += take
	return out

func _initialize() -> void:
	var pw = AddonWorld.new()
	var g = AddonBody.new(); g.position = Vector2(0, 220); g.is_static = true
	pw.add_child(g)
	var gs = AddonShape.new(); gs.rect_size = Vector2i(768, 100); g.add_child(gs)
	get_root().add_child(pw)
	await process_frame
	await process_frame
	pw.rebuild()
	var s = null
	for b in pw.world.bodies:
		if b.is_static: s = b.shapes[0]; break
	print("形状 %d px，aabb %s" % [s.pixel_count(), str(s.local_aabb())])

	var N := 5
	var t: int = Time.get_ticks_usec()
	for i in N: byte_build(s)
	var tb: float = (Time.get_ticks_usec() - t) / float(N) / 1000.0
	t = Time.get_ticks_usec()
	for i in N: bit_build(s)
	var tt: float = (Time.get_ticks_usec() - t) / float(N) / 1000.0
	print("  建网格：字节 %6.2f ms   位 %6.2f ms   倍数 %.2f" % [tb, tt, tb / maxf(tt, 0.001)])

	var bg = byte_build(s)
	var wg = bit_build(s)
	t = Time.get_ticks_usec()
	for i in N: byte_clear(bg, 768, 100)
	var cb: float = (Time.get_ticks_usec() - t) / float(N) / 1000.0
	t = Time.get_ticks_usec()
	for i in N: bit_clear(wg, 12, 768, 100)
	var ct: float = (Time.get_ticks_usec() - t) / float(N) / 1000.0
	print("  全宽清零：字节 %6.2f ms   位 %6.2f ms   倍数 %.2f" % [cb, ct, cb / maxf(ct, 0.001)])
	quit(0)

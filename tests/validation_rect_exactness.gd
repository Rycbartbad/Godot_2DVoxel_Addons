extends SceneTree
const Bits := preload("res://src/core/pixel_bits.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const PixelChunk := preload("res://src/core/pixel_chunk.gd")
const GreedyRects := preload("res://src/core/greedy_rects.gd")

func _comb(teeth: int) -> PixelShape:
	var s := PixelShape.new()
	for i in teeth:
		for y in 10:
			for x in 2:
				s.set_pixel(i * 4 + x, y, 1)
	for x in (teeth * 4):
		for y in 2:
			s.set_pixel(x, 8 + y, 1)
	return s

func _validate(shape: PixelShape, rects: Array) -> Dictionary:
	var pixels := {}
	for k: int in shape.chunks:
		var c: PixelChunk = shape.chunks[k]
		var bx := PixelShape.key_x(k) << 3
		var by := PixelShape.key_y(k) << 3
		var bits: int = c.occ
		while bits != 0:
			var i := Bits.first_bit_index(bits)
			bits &= bits - 1
			pixels[Vector2i(bx + (i & 7), by + (i >> 3))] = true
	var covered := {}
	for r: Rect2 in rects:
		for y in range(int(r.position.y), int(r.end.y)):
			for x in range(int(r.position.x), int(r.end.x)):
				var key := Vector2i(x, y)
				covered[key] = int(covered.get(key, 0)) + 1
	var phantom := 0
	var overlap := 0
	for key2: Vector2i in covered:
		var n: int = covered[key2]
		if n > 1:
			overlap += 1
		if not pixels.has(key2):
			phantom += 1
	var missing := 0
	for key3: Vector2i in pixels:
		if not covered.has(key3):
			missing += 1
	return {"pixels": pixels.size(), "phantom": phantom, "missing": missing, "overlap": overlap}

func _initialize() -> void:
	print("=== 矩形预算 (max_rects=64) 触发后的表现 ===")
	print("%-14s %7s %7s %8s %8s %8s" % ["shape", "pixels", "rects", "phantom", "missing", "overlap"])
	for teeth in [10, 20, 40, 100, 200]:
		var s := _comb(teeth)
		var r := GreedyRects.decompose(s, 64)
		var v := _validate(s, r.rects)
		print("%-14s %7d %7d %8d %8d %8d" % ["comb%d" % teeth, v["pixels"], r.rect_count(), v["phantom"], v["missing"], v["overlap"]])
	quit(0)

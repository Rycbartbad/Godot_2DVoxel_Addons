extends SceneTree
## 诊断：贪心矩形分解对凹陷形状是否精确

const Bits := preload("res://src/core/pixel_bits.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const GreedyRects := preload("res://src/core/greedy_rects.gd")

func _make(kind: String) -> PixelShape:
	var s := PixelShape.new()
	match kind:
		"L":
			for y in 12:
				for x in 4:
					s.set_pixel(x, y, 1)
			for x in 12:
				for y in 4:
					s.set_pixel(x, y, 1)
		"U":
			for y in 12:
				for x in 12:
					if x < 3 or x >= 9 or y < 3:
						s.set_pixel(x, y, 1)
		"donut":
			for y in 16:
				for x in 16:
					var dx := x - 7.5
					var dy := y - 7.5
					var d := sqrt(dx * dx + dy * dy)
					if d < 8.0 and d > 4.0:
						s.set_pixel(x, y, 1)
		"comb":
			for i in 20:
				for y in 10:
					for x in 2:
						s.set_pixel(i * 4 + x, y, 1)
			for x in 80:
				for y in 2:
					s.set_pixel(x, 8 + y, 1)
		"stair":
			for i in 16:
				for y in (i + 1):
					for x in (i + 1):
						if x == i or y == i:
							s.set_pixel(x, y, 1)
		"blob":
			for y in 40:
				for x in 40:
					var dx := x - 19.5
					var dy := y - 19.5
					var ang := atan2(dy, dx)
					var r := 15.0 + 6.0 * sin(ang * 5.0)
					if sqrt(dx * dx + dy * dy) < r:
						s.set_pixel(x, y, 1)
	return s

func _validate(shape: PixelShape, rects: Array) -> Dictionary:
	var pixels := {}
	for k: int in shape.chunks:
		var c = shape.chunks[k]
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
	for key: Vector2i in covered:
		var n: int = covered[key]
		if n > 1:
			overlap += 1
		if not pixels.has(key):
			phantom += 1
	var missing := 0
	for key2: Vector2i in pixels:
		if not covered.has(key2):
			missing += 1
	return {"pixels": pixels.size(), "phantom": phantom, "missing": missing, "overlap": overlap}

func _initialize() -> void:
	print("=== 矩形分解精确性诊断 ===")
	print("%-8s %7s %8s %8s %8s %8s" % ["shape", "pixels", "rects", "phantom", "missing", "overlap"])
	for kind in ["L", "U", "donut", "comb", "stair", "blob"]:
		var s := _make(kind)
		var r := GreedyRects.decompose(s, 0)
		var v := _validate(s, r.rects)
		print("%-8s %7d %8d %8d %8d %8d" % [kind, v["pixels"], r.rect_count(), v["phantom"], v["missing"], v["overlap"]])
	print("\n=== 开启 64 矩形预算后（PWorld 默认值）===")
	print("%-8s %7s %8s %8s %8s %8s" % ["shape", "pixels", "rects", "phantom", "missing", "overlap"])
	for kind in ["L", "U", "donut", "comb", "stair", "blob"]:
		var s := _make(kind)
		var r := GreedyRects.decompose(s, 64)
		var v := _validate(s, r.rects)
		print("%-8s %7d %8d %8d %8d %8d" % [kind, v["pixels"], r.rect_count(), v["phantom"], v["missing"], v["overlap"]])
	quit(0)

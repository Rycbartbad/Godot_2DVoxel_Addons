extends SceneTree
## 滚轮能调到的整个范围（1..40）都要能画出正确的一块
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const PixelChunk := preload("res://src/core/pixel_chunk.gd")
const Bits := preload("res://src/core/pixel_bits.gd")
const Editor := preload("res://src/core/pixel_editor.gd")

func _world_stats(world: PWorld) -> Array:
	var cells := {}
	for b: PBody in world.bodies:
		for s: PixelShape in b.shapes:
			for k: int in s.chunks:
				var c: PixelChunk = s.chunks[k]
				var bx := (PixelShape.key_x(k) << 3) + int(b.position.x)
				var by := (PixelShape.key_y(k) << 3) + int(b.position.y)
				var bits: int = c.occ
				while bits != 0:
					var i := Bits.first_bit_index(bits)
					bits &= bits - 1
					cells[Vector2i(bx + (i & 7), by + (i >> 3))] = true
	var blobs := 0
	var seen := {}
	for start: Vector2i in cells:
		if seen.has(start):
			continue
		blobs += 1
		var stack: Array = [start]
		seen[start] = true
		while not stack.is_empty():
			var p: Vector2i = stack.pop_back()
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = p + d
				if cells.has(q) and not seen.has(q):
					seen[q] = true
					stack.append(q)
	return [cells.size(), blobs]

func _initialize() -> void:
	print("滚轮范围 1..40 的笔刷自检（一笔横划，世界坐标上必须是 1 块）")
	print(" 半径 | 直径 | 实际像素 | 理论约为 | 连通块")
	var bad := 0
	for r in [1, 2, 3, 6, 10, 20, 30, 40]:
		var world := PWorld.new()
		var tiles := {}
		var len := 120.0
		Editor.paint_canvas(world, tiles, Vector2(200, 200), Vector2(200 + len, 200), float(r), 1, 64)
		var st := _world_stats(world)
		var approx := int((2.0 * r * len) + PI * r * r)
		var ok: bool = st[1] == 1
		if not ok:
			bad += 1
		print("  %3d | %3d  | %8d | %8d | %d %s" % [r, r * 2, st[0], approx, st[1], "" if ok else "  <-- 断开!"])
	print("\n%s" % ("全部连续" if bad == 0 else "%d 个半径画出断裂!" % bad))
	quit(0)

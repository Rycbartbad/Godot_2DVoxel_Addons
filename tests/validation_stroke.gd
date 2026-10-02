extends SceneTree
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const PixelChunk := preload("res://src/core/pixel_chunk.gd")
const Bits := preload("res://src/core/pixel_bits.gd")
const Editor := preload("res://src/core/pixel_editor.gd")

## 把世界上所有像素按世界坐标收集起来做 4 邻域泛洪 —— 这才是"眼睛看到的块数"
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
	var total := cells.size()
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
	return [total, blobs]

func _paint(start: Vector2, end: Vector2, radius: float, label: String) -> void:
	var world := PWorld.new()
	var tiles := {}
	Editor.paint_canvas(world, tiles, start, end, radius, 1, 32)
	var st := _world_stats(world)
	print("  %-20s 半径 %.0f : 世界像素 %5d / 连通块 %d / Body %d" % [label, radius, st[0], st[1], world.bodies.size()])

func _initialize() -> void:
	print("=== 修复后：一笔画下去在**世界坐标**上应当是 1 块 ===")
	_paint(Vector2(10, 10), Vector2(10, 10), 6.0, "原地按一下")
	_paint(Vector2(30, 30), Vector2(34, 30), 6.0, "极短拖动(4px)")
	_paint(Vector2(10, 10), Vector2(60, 10), 6.0, "横向短划")
	_paint(Vector2(10, 10), Vector2(200, 10), 6.0, "横向长划")
	_paint(Vector2(5, 5), Vector2(100, 100), 4.0, "斜向长划")
	quit(0)

extends SceneTree
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const PixelChunk := preload("res://src/core/pixel_chunk.gd")
const Bits := preload("res://src/core/pixel_bits.gd")
const Editor := preload("res://src/core/pixel_editor.gd")

func _collect(world: PWorld) -> Dictionary:
	var cells := {}
	for b: PBody in world.bodies:
		for s: PixelShape in b.shapes:
			for k: int in s.chunks:
				var c: PixelChunk = s.chunks[k]
				var bx := (PixelShape.key_x(k) << 3) + int(round(b.position.x))
				var by := (PixelShape.key_y(k) << 3) + int(round(b.position.y))
				var bits: int = c.occ
				while bits != 0:
					var i := Bits.first_bit_index(bits)
					bits &= bits - 1
					cells[Vector2i(bx + (i & 7), by + (i >> 3))] = true
	return cells

func _canvas(from: Vector2, to: Vector2, r: float) -> Dictionary:
	var w := PWorld.new()
	Editor.paint_canvas(w, {}, from, to, r, 1, 64)
	return _collect(w)

func _stroke(from: Vector2, to: Vector2, r: float, offset: Vector2) -> Dictionary:
	var w := PWorld.new()
	var b := PBody.new()
	b.position = offset
	b.make_static()
	w.add_body(b, [PixelShape.new()])
	Editor.paint_into(b, from - b.position, to - b.position, r, 1)
	return _collect(w)

func _diff(a: Dictionary, b: Dictionary) -> int:
	var d := 0
	for k: Vector2i in a:
		if not b.has(k):
			d += 1
	for k: Vector2i in b:
		if not a.has(k):
			d += 1
	return d

func _initialize() -> void:
	print("光标位置用非整数（模拟真实鼠标）")
	print(" 半径 |  起点        | 旧(-0.5) 差 | 新(floor) 差")
	for r in [3, 6, 20]:
		for from in [Vector2(130.3, 130.7), Vector2(200.49, 90.51), Vector2(77.9, 210.2)]:
			var to: Vector2 = from + Vector2(120.0, 40.0)
			var ref := _canvas(from, to, float(r))
			var old := _stroke(from, to, float(r), from - Vector2(0.5, 0.5))
			var neu := _stroke(from, to, float(r), from.floor())
			print("  %3d | %s | %11d | %10d %s" % [
				r, str(from), _diff(ref, old), _diff(ref, neu),
				"  <-- 修好了" if _diff(ref, neu) == 0 else ""])
	quit(0)

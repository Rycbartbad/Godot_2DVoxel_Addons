extends SceneTree
## 6.4 ms 是"删了多少像素"决定，还是"形状多大"决定？
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _ground() -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, 800, 40), 1)
	return s

func _run(label: String, mask_px: int) -> void:
	var w := PWorld.new()
	w.gravity = Vector2.ZERO
	var b := PBody.new()
	w.add_body(b, [_ground()])
	var m := {}
	var n := 0
	for y in 40:
		for x in 800:
			if n >= mask_px:
				break
			m[Vector2i(x, y)] = true
			n += 1
	var t0 := Time.get_ticks_usec()
	w.fracture_pixels(b, {b.shapes[0]: m}, 0.0, true)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("  %-24s 删 %5d 像素 | 用时 %8.3f ms | 剩余 %6d 像素 | 矩形 %4d" % [
		label, mask_px, ms, b.shapes[0].pixel_count(), b.rects.size()])

func _initialize() -> void:
	print("=== 同一个 800x40 地面，删不同大小的块 ===")
	for n in [1, 100, 1000, 4000]:
		_run("删 %d 像素" % n, n)
	quit(0)

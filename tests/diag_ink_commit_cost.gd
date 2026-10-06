extends SceneTree
## 量 fracture_pixels 在 ink-2 的实际几何尺寸上的成本（决定"个位帧率"的来源）
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const Destruction := preload("res://src/core/destruction.gd")

func _ground_shape() -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, 800, 40), 1)      # ink-2 的 Ground: 800x40
	return s

## 1 像素宽的斜线（ink 笔画的典型形状）
func _ink_line(len: int) -> PixelShape:
	var s := PixelShape.new()
	for i in len:
		s.set_pixel(i, i, 1)
	return s

func _time_fracture(label: String, shape: PixelShape, cuts: int) -> void:
	var w := PWorld.new()
	w.gravity = Vector2.ZERO
	var b := PBody.new()
	w.add_body(b, [shape])
	# 造 cuts 个"损伤掩码"（每次切一小块，模拟一次撞击的删除集）
	var masks: Array = []
	for c in cuts:
		var m := {}
		for y in range(c * 2, c * 2 + 2):
			for x in range(c * 3, c * 3 + 3):
				m[Vector2i(x, y)] = true
		masks.append(m)
	var total := 0.0
	var worst := 0.0
	for m in masks:
		var t0 := Time.get_ticks_usec()
		var r: Dictionary = w.fracture_pixels(b, {b.shapes[0]: m}, 0.0, true)
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		total += ms
		worst = maxf(worst, ms)
	print("  %-34s 像素 %6d | 矩形 %5d | 每刀 %7.2f ms | %d 刀合计 %8.2f ms | 碎片 %d" % [
		label, shape.pixel_count(), b.rects.size(), worst, cuts, total, b.shapes.size()])

func _initialize() -> void:
	print("=== fracture_pixels 在你的几何尺寸上的成本 ===")
	_time_fracture("Ground 800x40（= ink-2 地面）", _ground_shape(), 4)
	_time_fracture("画布 256x256 实心", (func() -> PixelShape:
		var s := PixelShape.new(); s.fill_rect(Rect2i(0, 0, 256, 256), 1); return s).call(), 4)
	_time_fracture("ink 斜线 64 像素（1 像素宽）", _ink_line(64), 4)
	_time_fracture("小碎片 8x8", (func() -> PixelShape:
		var s := PixelShape.new(); s.fill_rect(Rect2i(0, 0, 8, 8), 1); return s).call(), 4)
	print("")
	print("=== 参照：一次撞击可能同时打 2~4 个刚体（a/b 两侧 × 多个接触点）===")
	print("  4 刀 x 地面 = 上面的合计；若每刀 ~25 ms，一帧 4 刀就是 100 ms = 个位帧率")
	quit(0)

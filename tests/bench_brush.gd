extends SceneTree
## 画笔光栅化：新（到线段距离）vs 旧（沿线补点盖圆盘）。
## 换算法是为了修正确性（虚线 / 截断 / 边缘波动），但顺手要确认没有把性能换掉。
const PixelShape := preload("res://src/core/pixel_shape.gd")
const Brush := preload("res://src/core/brush.gd")

## 旧算法原样搬过来做对照（含它自己的 MAX_STEPS=256 截断）
const OLD_MAX_STEPS := 256

func _stamp_old(shape: PixelShape, center: Vector2, radius: float, material: int) -> int:
	var r := maxf(0.5, radius)
	var r2 := r * r
	var y0 := int(floor(center.y - r))
	var y1 := int(floor(center.y + r))
	var added := 0
	for y in range(y0, y1 + 1):
		var py := float(y) + 0.5 - center.y
		var py2 := py * py
		if py2 > r2:
			continue
		var half := sqrt(r2 - py2)
		var xa := int(ceil(center.x - half - 0.5))
		var xb := int(floor(center.x + half - 0.5))
		if xa > xb:
			continue
		for x in range(xa, xb + 1):
			var dx := float(x) + 0.5 - center.x
			if dx * dx + py2 > r2:
				continue
			if shape.add_pixel(x, y, material):
				added += 1
	return added

func _stroke_old(shape: PixelShape, from: Vector2, to: Vector2, radius: float, material: int) -> int:
	var r := maxf(0.5, radius)
	var delta := to - from
	var length := delta.length()
	var step := maxf(1.0, r * 0.5)
	var steps := int(ceil(length / step))
	if steps > OLD_MAX_STEPS:
		steps = OLD_MAX_STEPS
	if steps <= 0:
		return _stamp_old(shape, to, r, material)
	var added := 0
	for i in range(steps + 1):
		added += _stamp_old(shape, from.lerp(to, float(i) / float(steps)), r, material)
	return added

func _time(use_new: bool, radius: float, length: float, reps: int) -> float:
	var a := Vector2(0.0, 0.0)
	var bb := Vector2(length, 0.0)
	var best := 1.0e18
	for rep in reps:
		var s := PixelShape.new()
		var t0 := Time.get_ticks_usec()
		if use_new:
			Brush.stroke_circle(s, a, bb, radius, 1)
		else:
			_stroke_old(s, a, bb, radius, 1)
		var dt := float(Time.get_ticks_usec() - t0)
		best = minf(best, dt)
	return best

func _initialize() -> void:
	print("=== 画笔光栅化 A/B（一条水平笔画，us，取 5 次最小值）===")
	print("%-8s %-10s %-12s %-12s %s" % ["半径", "长度", "旧(补点)", "新(距离)", "新/旧"])
	var total_old := 0.0
	var total_new := 0.0
	for spec in [[1, 10], [1, 200], [1, 800], [6, 200], [20, 200], [40, 200], [6, 800], [40, 800]]:
		var r: float = spec[0]
		var L: float = spec[1]
		var o := _time(false, r, L, 5)
		var n := _time(true, r, L, 5)
		total_old += o
		total_new += n
		print("%-8.0f %-10.0f %-12.1f %-12.1f %.2fx" % [r, L, o, n, n / maxf(0.01, o)])
	print("合计: 旧 %.1f us | 新 %.1f us | 新/旧 %.2fx" % [total_old, total_new, total_new / maxf(0.01, total_old)])
	quit(0)

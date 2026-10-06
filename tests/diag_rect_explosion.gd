extends SceneTree
## 矩形数爆炸时 decompose/_merge_pass 的代价 —— 找"卡死"。
const PixelShape := preload("res://src/core/pixel_shape.gd")
const GreedyRects := preload("res://src/core/greedy_rects.gd")

func _checker(w: int, h: int, period: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			if ((x / period) + (y / period)) % 2 == 0:
				s.set_pixel(x, y, 1)
	return s

func _ms(t0: int) -> float:
	return float(Time.get_ticks_usec() - t0) / 1000.0

func _initialize() -> void:
	print("=== 棋盘（每个格子一个矩形 -> 矩形数 = 格数）===")
	for period in [16, 8, 4, 2]:
		var s := _checker(256, 256, period)
		var cells: int = (256 / period) * (256 / period)
		var n_expect: int = cells / 2
		var t := Time.get_ticks_usec()
		var r: GreedyRects.Result = GreedyRects.decompose(s, 0)
		var ms := _ms(t)
		print("  period=%-3d 像素=%6d 矩形=%5d  期望≈%5d  decompose = %8.3f ms  budget_exceeded=%s" % [
			period, s.pixel_count(), r.rects.size(), n_expect, ms, str(r.budget_exceeded)])
	quit(0)

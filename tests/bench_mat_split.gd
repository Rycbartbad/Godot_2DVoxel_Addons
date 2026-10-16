extends SceneTree
## bench：按材质分解（op 4）与普通分解（op 2）的代价对比。
##
## ⚠️ 为什么要量：这条 op 每笔破坏都要走一次，而它比 op 2 多传一份**材质字节**
##    （每块 64 字节）。"多了多少"必须用数字说话，否则就是拿手感赌。
const PixelShape := preload("res://src/core/pixel_shape.gd")
const GreedyRects := preload("res://src/core/greedy_rects.gd")

func _shape(w: int, h: int, mats: int) -> PixelShape:
	var s := PixelShape.new()
	if mats <= 1:
		s.fill_rect(Rect2i(0, 0, w, h), 1)
	else:
		var band := maxi(1, h / mats)
		for i in mats:
			s.fill_rect(Rect2i(0, i * band, w, band if i < mats - 1 else h - i * band), i + 1)
	return s

func _time(f: Callable, iters: int) -> float:
	f.call()                                  # 预热（缓存/懒加载）
	var t0 := Time.get_ticks_usec()
	for i in iters:
		f.call()
	return float(Time.get_ticks_usec() - t0) / float(iters) / 1000.0

func _report(label: String, s: PixelShape, iters: int) -> void:
	var n := s.chunks.size()
	var t2 := _time(func() -> void: GreedyRects.decompose(s, 64), iters)
	var tm := _time(func() -> void: GreedyRects.decompose_material(s, 64), iters)
	var r := GreedyRects.decompose_material(s, 64)
	print("%-22s chunks=%-5d 矩形=%-5d decompose %7.3f ms   decompose_material %7.3f ms  (x%.2f)" % [
		label, n, r.rects.size(), t2, tm, tm / maxf(t2, 0.0001)])
	print("      材质标签: %s" % str(r.mats.slice(0, 8)))

func _initialize() -> void:
	print("原生调用 %d 次 / 回退 %d 次" % [GreedyRects.native_calls, GreedyRects.native_fallbacks])
	_report("768x100 单材质", _shape(768, 100, 1), 20)
	_report("768x100 双材质", _shape(768, 100, 2), 20)
	_report("768x100 四材质", _shape(768, 100, 4), 20)
	_report("48x48 单材质", _shape(48, 48, 1), 200)
	_report("12x12 双材质", _shape(12, 12, 2), 400)
	_report("4x4 单材质", _shape(4, 4, 1), 400)
	quit(0)

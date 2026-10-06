extends SceneTree
## rebuild 的两大块分开量：MassProps（逐像素质量属性） vs GreedyRects.decompose（逐像素矩形）
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const MassProps := preload("res://src/core/mass_props.gd")
const GreedyRects := preload("res://src/core/greedy_rects.gd")

func _shape(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _run(label: String, gw: int, gh: int, is_static: bool) -> void:
	var w := PWorld.new()
	w.gravity = Vector2.ZERO
	var b := PBody.new()
	if is_static:
		b.make_static()
	var s := _shape(gw, gh)
	w.add_body(b, [s])
	var n_px := s.pixel_count()

	var t0 := Time.get_ticks_usec()
	var p = MassProps.compute(s, w.density_callable(), w.friction_callable(), w.restitution_callable())
	var ms_mass := float(Time.get_ticks_usec() - t0) / 1000.0

	var t1 := Time.get_ticks_usec()
	var r = GreedyRects.decompose(s, 64)
	var ms_rect := float(Time.get_ticks_usec() - t1) / 1000.0

	var t2 := Time.get_ticks_usec()
	b.rebuild([s], w.density_callable(), 64, Rect2i(), w.friction_callable(), w.restitution_callable(), {})
	var ms_rb := float(Time.get_ticks_usec() - t2) / 1000.0

	print("  %-26s 像素 %6d | MassProps %7.3f | decompose %7.3f（矩形 %3d）| rebuild 整体 %7.3f ms" % [
		label, n_px, ms_mass, ms_rect, r.rects.size(), ms_rb])

func _initialize() -> void:
	print("=== 动态体 ===")
	_run("800x40 动态", 800, 40, false)
	_run("200x200 动态", 200, 200, false)
	print("=== 静态体（ink-2 的地面就是这种）===")
	_run("800x40 静态", 800, 40, true)
	_run("200x200 静态", 200, 200, true)
	quit(0)

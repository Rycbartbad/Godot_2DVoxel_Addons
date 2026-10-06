extends SceneTree
## 静态 rebuild 的 1.96 ms 里，除了 decompose(0.28) 还有 1.67 ms —— 在哪？
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const GreedyRects := preload("res://src/core/greedy_rects.gd")

func _shape(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _run(label: String, gw: int, gh: int) -> void:
	var w := PWorld.new()
	w.gravity = Vector2.ZERO
	var b := PBody.new()
	b.make_static()
	var s := _shape(gw, gh)
	w.add_body(b, [s])

	var t := Time.get_ticks_usec()
	s.touch()
	var ms_touch := float(Time.get_ticks_usec() - t) / 1000.0
	t = Time.get_ticks_usec()
	var mat: int = b._first_material([s])
	var ms_mat := float(Time.get_ticks_usec() - t) / 1000.0
	t = Time.get_ticks_usec()
	b.refresh_com()
	var ms_com := float(Time.get_ticks_usec() - t) / 1000.0
	t = Time.get_ticks_usec()
	b.update_aabb()
	var ms_aabb := float(Time.get_ticks_usec() - t) / 1000.0
	t = Time.get_ticks_usec()
	var r = GreedyRects.decompose(s, 64)
	var ms_rect := float(Time.get_ticks_usec() - t) / 1000.0
	t = Time.get_ticks_usec()
	b.rebuild([s], w.density_callable(), 64, Rect2i(), w.friction_callable(), w.restitution_callable(), {})
	var ms_all := float(Time.get_ticks_usec() - t) / 1000.0
	print("  %-18s 像素 %6d | touch %6.3f | _first_material %6.3f | refresh_com %6.3f | update_aabb %6.3f | decompose %6.3f | rebuild 整体 %6.3f ms" % [
		label, gw * gh, ms_touch, ms_mat, ms_com, ms_aabb, ms_rect, ms_all])

func _initialize() -> void:
	print("=== 静态 rebuild 的分段 ===")
	_run("800x40", 800, 40)
	_run("200x200", 200, 200)
	_run("800x400（10 倍）", 800, 400)
	quit(0)

extends SceneTree
## fracture_pixels 的 5.8 ms 到底花在哪一段？
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const Destruction := preload("res://src/core/destruction.gd")

func _ground(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _breakdown(label: String, gw: int, gh: int) -> void:
	var w := PWorld.new()
	w.gravity = Vector2.ZERO
	var b := PBody.new()
	var s := _ground(gw, gh)
	w.add_body(b, [s])
	var mask := {Vector2i(100, 20): true}      # 只删 1 个像素

	# ① 删除（fracture_pixels 自己的循环）
	var t0 := Time.get_ticks_usec()
	s.clear_pixel(100, 20)
	var ms_del := float(Time.get_ticks_usec() - t0) / 1000.0

	# ② 局部连通检查（第 3112 行那一步）
	var t1 := Time.get_ticks_usec()
	var st: int = Destruction.local_connectivity(s, Rect2i(99, 19, 3, 3), 4)
	var ms_lc := float(Time.get_ticks_usec() - t1) / 1000.0

	# ③ 重建（质量属性 + AABB + 贪心矩形）
	var t2 := Time.get_ticks_usec()
	b.rebuild([s], w.density_callable(), 0, Rect2i(), w.friction_callable(), w.restitution_callable(), {})
	var ms_rb := float(Time.get_ticks_usec() - t2) / 1000.0

	print("  %-22s 像素 %6d | 删1像素 %6.3f | local_connectivity %6.3f (状态 %d) | rebuild %7.3f | 小计 %6.3f ms" % [
		label, gw * gh, ms_del, ms_lc, st, ms_rb, ms_del + ms_lc + ms_rb])

func _initialize() -> void:
	print("=== 分段（删 1 个像素）===")
	_breakdown("800x40（ink-2 地面）", 800, 40)
	_breakdown("400x40", 400, 40)
	_breakdown("800x10", 800, 10)
	_breakdown("200x200", 200, 200)
	print("")
	print("=== 对照：整段 fracture_pixels（同一个形状，删 1 像素）===")
	for spec in [[800, 40], [200, 200]]:
		var w2 := PWorld.new()
		w2.gravity = Vector2.ZERO
		var b2 := PBody.new()
		w2.add_body(b2, [_ground(spec[0], spec[1])])
		var t := Time.get_ticks_usec()
		w2.fracture_pixels(b2, {b2.shapes[0]: {Vector2i(100, 20): true}}, 0.0, true)
		print("  %dx%-4d -> 端到端 %7.3f ms" % [spec[0], spec[1], float(Time.get_ticks_usec() - t) / 1000.0])
	quit(0)

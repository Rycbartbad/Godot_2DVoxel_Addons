extends SceneTree
## 分阶段计时：fracture/detach 的钱花在哪。
## 用同一个 200x200 形状（40000 像素），各阶段分别跑一次。
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const Destruction := preload("res://src/core/destruction.gd")

func _slab(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _initialize() -> void:
	var dmg = Destruction.Damage.circle(Vector2(100, 100), 6.0)
	var w := PWorld.new()
	var b := PBody.new()
	w.add_body(b, [_slab(200, 200)], Callable(), true)

	var t := 0
	t = Time.get_ticks_usec()
	var ex: PixelShape = Destruction.extract_damage(b.shapes[0], dmg)
	print("extract_damage   = %.3f ms（捡到 %d 像素）" % [(Time.get_ticks_usec() - t) / 1000.0, ex.pixel_count()])

	var s2 := _slab(200, 200)
	t = Time.get_ticks_usec()
	var removed := Destruction.apply_damage(s2, dmg)
	print("apply_damage     = %.3f ms（删掉 %d 像素）" % [(Time.get_ticks_usec() - t) / 1000.0, removed])

	var s3 := _slab(200, 200)
	t = Time.get_ticks_usec()
	var parts: Array = Destruction.split(s3)
	print("split（全量连通）= %.3f ms（%d 块）" % [(Time.get_ticks_usec() - t) / 1000.0, parts.size()])

	var s4 := _slab(200, 200)
	var b4 := PBody.new()
	w.add_body(b4, [s4], Callable(), true)
	Destruction.apply_damage(s4, dmg)
	t = Time.get_ticks_usec()
	b4.rebuild(b4.shapes, w.density_callable(), w.max_rects_per_shape)
	print("rebuild（含推 Rapier）= %.3f ms" % [(Time.get_ticks_usec() - t) / 1000.0])

	var s5 := _slab(200, 200)
	var probe := Rect2i(94, 94, 16, 16)
	t = Time.get_ticks_usec()
	var tb := Destruction.touches_boundary(s5, probe)
	print("touches_boundary = %.3f ms（%s）" % [(Time.get_ticks_usec() - t) / 1000.0, str(tb)])

	# 整体（对照）
	var w2 := PWorld.new()
	var b2 := PBody.new()
	w2.add_body(b2, [_slab(200, 200)], Callable(), true)
	t = Time.get_ticks_usec()
	w2.fracture(b2, dmg)
	print("fracture 整体    = %.3f ms" % [(Time.get_ticks_usec() - t) / 1000.0])
	quit(0)

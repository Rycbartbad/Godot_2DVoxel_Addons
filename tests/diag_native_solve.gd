extends SceneTree
## 用会分歧的场景（6x5 箱阵）逐帧定位第一次分歧
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _shape(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

func _mk(use_native_solve: bool) -> PWorld:
	var w := PWorld.new()
	w.sleeping_enabled = false
	w.use_threads = false
	w.ccd_enabled = false
	w.use_native_broadphase = true
	w.use_native_solve = use_native_solve
	var g := PBody.new()
	g.position = Vector2(-200.0, 0.0)
	g.make_static()
	w.add_body(g, [_shape(400, 40)])
	for r in 5:
		for c in 6:
			var b := PBody.new()
			b.position = Vector2(-42.0 + float(c) * 14.0, -14.0 - float(r) * 14.0)
			w.add_body(b, [_shape(14, 14)])
	return w

func _snap(w: PWorld) -> Array:
	var out: Array = []
	for b in w.bodies:
		if b.is_static:
			continue
		out.append([b.linear_velocity.x, b.linear_velocity.y, b.angular_velocity,
			b.position.x, b.position.y, b.rotation])
	return out

func _initialize() -> void:
	var wa := _mk(false)
	var wb := _mk(true)
	print("步 | 最大差 | 位置 | 体号 | 字段 | 流形 对象/扩展")
	var first := -1
	var no_warm := OS.get_cmdline_user_args().has("--nowarm")
	for s in 40:
		wa.step(1.0 / 60.0)
		wb.step(1.0 / 60.0)
		if no_warm:
			wa.solver._warm.clear()
			if wb._sv_phys != null:
				wb._sv_phys.clear_warm()
		var a := _snap(wa)
		var b := _snap(wb)
		var d := 0.0
		var bi := -1
		var bk := -1
		for i in a.size():
			for k in 6:
				var dd: float = absf(float(a[i][k]) - float(b[i][k]))
				if dd > d:
					d = dd
					bi = i
					bk = k
		if d > 0.0 and first < 0:
			first = s
		if s < 8 or s % 5 == 0 or (d > 0.0 and s <= first + 2):
			print("%2d | %.9f | %s | 体%d | 字段%d | %d/%d" % [
				s, d, ("首次分歧" if s == first else "        "), bi, bk,
				wa.manifolds.size(), wb._bp_count])
	print("首次分歧步 = %d" % first)
	quit(0)

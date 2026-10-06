extends SceneTree
## 把所有闸门一次量清楚：质量过关**且**在动，到底会不会被删？
## 以及每条闸门各自拦下什么（甲方："speed=1 而且它动了，还是没删"）。
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _shape(w: int, h: int, mat := 1) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), mat)
	return s

func _motion(b) -> float:
	return b.linear_velocity.length() + absf(b.angular_velocity) * b.bounding_radius()

func _initialize() -> void:
	print("=== 逐条闸门（mass=20 / speed=1，碎片 2x2 密度2.5 -> 质量 10）===")
	var cases := [
		["① 静止", 0.0, false, false],
		["② 以 5 px/s 动", 5.0, false, false],
		["③ 以 100 px/s 动", 100.0, false, false],
		["④ 以 5 px/s 动 + 冻着", 5.0, true, false],
		["⑤ 以 5 px/s 动 + 挂着关节", 5.0, false, true],
	]
	for c in cases:
		var w := PWorld.new()
		w.gravity = Vector2(0, 300)
		w.set_material_density(1, 2.5)
		var g := PBody.new()
		g.make_static()
		w.add_body(g, [_shape(400, 40, 1)])
		var f := PBody.new()
		f.position = Vector2(100, -60)
		w.add_body(f, [_shape(2, 2, 1)])
		# 先落定，再给速度（否则会撞到地面就停）
		for k in 200:
			w.step(1.0 / 60.0)
		var anchor: PBody = null
		if bool(c[3]):
			anchor = PBody.new()
			anchor.make_static()
			w.add_body(anchor, [_shape(4, 4, 1)])
			w.add_weld(f, anchor, f.position)
		if bool(c[2]):
			w.freeze(f)
		f.linear_velocity = Vector2(float(c[1]), 0.0)
		w.debris_max_mass = 20.0
		w.debris_min_speed = 1.0
		var before := w.bodies.size()
		w.step(1.0 / 60.0)
		print("  %-26s 质量 %6.2f motion %8.3f frozen=%-5s -> %s（removed=%d）" % [
			c[0], f.mass, _motion(f), str(f.frozen),
			"**已清**" if not w.bodies.has(f) else "没清", w.last_debris_removed])
	print("")
	print("=== 质量闸门：质量刚好在阈值两侧（都在动，speed=1）===")
	for spec in [[2, 20.0], [4, 20.0], [4, 50.0], [8, 200.0]]:
		var size: int = spec[0]
		var mass: float = spec[1]
		var w2 := PWorld.new()
		w2.gravity = Vector2(0, 300)
		w2.set_material_density(1, 2.5)
		var g2 := PBody.new()
		g2.make_static()
		w2.add_body(g2, [_shape(400, 40, 1)])
		var f2 := PBody.new()
		f2.position = Vector2(100, -60)
		w2.add_body(f2, [_shape(size, size, 1)])
		for k in 200:
			w2.step(1.0 / 60.0)
		f2.linear_velocity = Vector2(5, 0)
		w2.debris_max_mass = mass
		w2.debris_min_speed = 1.0
		w2.step(1.0 / 60.0)
		print("  %dx%-2d 质量 %7.2f  debris_max_mass=%-6s -> %s" % [
			size, size, f2.mass, str(mass), "**已清**" if not w2.bodies.has(f2) else "没清"])
	quit(0)

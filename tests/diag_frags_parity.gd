extends SceneTree
## frags:240 逐帧定位首次分歧
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

func _build(native: bool) -> PWorld:
	var world := PWorld.new()
	world.sleeping_enabled = false
	world.ccd_enabled = false
	world.use_threads = false
	world.use_native_solve = native
	world.use_native_broadphase = native
	world.use_native_collide = native
	var g := PBody.new()
	g.position = Vector2(-2000.0, 0.0)
	g.make_static()
	world.add_body(g, [_block(4000, 40)])
	for i in 240:
		var f := PBody.new()
		f.position = Vector2(-1200.0 + float(i % 60) * 12.0, -400.0 - float(i / 60) * 14.0)
		world.add_body(f, [_block(4, 4)])
		f.linear_velocity = Vector2(-120.0 + float(i % 13) * 20.0, 100.0)
	return world

func _sum(w: PWorld) -> float:
	var acc := 0.0
	for b in w.bodies:
		if b.is_static:
			continue
		acc += b.position.x * 0.001 + b.position.y * 0.01 + b.rotation * 0.1 \
			+ b.linear_velocity.x * 0.0001 + b.linear_velocity.y * 0.00001
	return acc

func _initialize() -> void:
	var a := _build(false)
	var b := _build(true)
	var first := -1
	for i in 300:
		a.step(1.0 / 60.0)
		b.step(1.0 / 60.0)
		var sa := _sum(a)
		var sb := _sum(b)
		if sa != sb and first < 0:
			first = i
			print("首次分歧: 第 %d 步  差 %.15f" % [i, sb - sa])
		if i == 299:
			print("末态: GS %.12f | 原生 %.12f | 差 %.15f" % [sa, sb, sb - sa])
	print("首次分歧步: %d" % first)
	quit(0)

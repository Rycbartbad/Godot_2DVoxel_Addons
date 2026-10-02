extends SceneTree
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

func _scene(piles: int, per_pile: int, threads: bool, sleeping: bool, ccd: bool) -> PWorld:
	var world := PWorld.new()
	world.use_threads = threads
	world.sleeping_enabled = sleeping
	world.ccd_enabled = ccd
	var cols := int(ceil(sqrt(float(piles))))
	for p in piles:
		var gx := (p % cols) * 90.0
		var gy := float(p / cols) * 260.0
		var g := PBody.new()
		g.position = Vector2(gx, gy + 140.0)
		g.make_static()
		world.add_body(g, [_block(60, 8)])
		for i in per_pile:
			var b := PBody.new()
			b.position = Vector2(gx + 10.0, gy + 120.0 - i * 16.0)
			world.add_body(b, [_block(14, 14)])
	for i in 120:
		world.step(1.0 / 60.0)
	return world

func _time(world: PWorld, steps: int) -> float:
	var t0 := Time.get_ticks_usec()
	for i in steps:
		world.step(1.0 / 60.0)
	return (Time.get_ticks_usec() - t0) / 1000.0 / float(steps)

func _initialize() -> void:
	print("=== CCD 代价 A/B (16 核) ===")
	for cfg in [[16, 5]]:
		for ccd in [false, true]:
			var w1 := _scene(cfg[0], cfg[1], false, false, ccd)
			var ms := _time(w1, 40)
			var awake := 0
			for b in w1.bodies:
				if not b.is_static and b.awake:
					awake += 1
			print("  ccd=%-5s substeps=%2d: %7.3f ms/step  (%d 流形, %d 清醒)" % [
				str(ccd), w1.last_substeps, ms, w1.manifolds.size(), awake])
	print("\n=== 岛并行 A/B（关休眠，多个独立堆）===")
	for cfg in [[16, 5], [36, 5]]:
		var ws := _scene(cfg[0], cfg[1], false, false, false)
		var s_ms := _time(ws, 40)
		var wp := _scene(cfg[0], cfg[1], true, false, false)
		var p_ms := _time(wp, 40)
		print("  %2d 堆 x %d (%3d 动态体, %3d 流形, %2d 岛): 串行 %7.3f | 并行 %7.3f | 加速 %.2fx" % [
			cfg[0], cfg[1], wp.bodies.size(), wp.manifolds.size(), wp.last_parallel_tasks, s_ms, p_ms, s_ms / maxf(0.001, p_ms)])
	quit(0)

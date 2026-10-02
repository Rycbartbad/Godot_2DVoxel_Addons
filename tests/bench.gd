extends SceneTree
## 性能基准：给出框架文档里引用的真实数字。

const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const Destruction := preload("res://src/core/destruction.gd")
const GreedyRects := preload("res://src/core/greedy_rects.gd")
const MassProps := preload("res://src/core/mass_props.gd")

func _block(w: int, h: int, mat: int = 1) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, mat)
	return s

func _initialize() -> void:
	print("=== 2D pixel physics benchmark (Godot 4.7.2, GDScript, headless) ===")
	_bench_decompose()
	_bench_destruction()
	_bench_physics()
	quit(0)

func _bench_decompose() -> void:
	print("\n[rectangle decomposition + mass props]")
	for size in [16, 32, 64]:
		var s := _block(size, size)
		var t0 := Time.get_ticks_usec()
		var r: GreedyRects.Result = GreedyRects.decompose(s)
		var t1 := Time.get_ticks_usec()
		var p := MassProps.compute(s)
		var t2 := Time.get_ticks_usec()
		print("  %dx%d (%d px): decompose %6.3f ms -> %d rects | mass props %6.3f ms | I=%.0f" % [
			size, size, size * size, (t1 - t0) / 1000.0, r.rect_count(), (t2 - t1) / 1000.0, p.inertia])

func _bench_destruction() -> void:
	print("\n[destruction + connectivity split]")
	for cfg in [[64, 64, 6.0], [128, 128, 12.0], [192, 192, 20.0]]:
		var s := _block(cfg[0], cfg[1])
		var t0 := Time.get_ticks_usec()
		var removed: int = Destruction.apply_damage(s, Destruction.Damage.circle(
			Vector2(cfg[0] * 0.5, cfg[1] * 0.5), cfg[2]))
		var t1 := Time.get_ticks_usec()
		var parts: Array = Destruction.split(s, 4)
		var t2 := Time.get_ticks_usec()
		var total := 0
		for p: PixelShape in parts:
			total += p.pixel_count()
		print("  %dx%d, blast r=%.0f: removed %d px | mask+apply %6.3f ms | split %6.3f ms -> %d parts (kept %d px)" % [
			cfg[0], cfg[1], cfg[2], removed, (t1 - t0) / 1000.0, (t2 - t1) / 1000.0, parts.size(), total])

func _bench_physics() -> void:
	print("\n[physics pipeline]")
	for count in [8, 32, 96]:
		var world := PWorld.new()
		var g := PBody.new()
		g.position = Vector2(0, 400)
		g.make_static()
		world.add_body(g, [_block(600, 32)])
		for i in count:
			var b := PBody.new()
			b.position = Vector2(30 + (i % 12) * 44, 340 - (i / 12) * 30)
			world.add_body(b, [_block(28, 28)])
		# 预热 + 让堆叠落定
		for i in 240:
			world.step(1.0 / 60.0)
		var t0 := Time.get_ticks_usec()
		for i in 120:
			world.step(1.0 / 60.0)
		var t1 := Time.get_ticks_usec()
		var awake := 0
		for b2 in world.bodies:
			if not b2.is_static and b2.awake:
				awake += 1
		print("  %3d dynamic bodies: %6.3f ms/step (%d manifolds, %d contacts, %d awake after settle)" % [
			count, (t1 - t0) / 1000.0 / 120.0, world.manifolds.size(), world.last_contacts, awake])

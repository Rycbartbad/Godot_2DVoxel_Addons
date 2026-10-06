extends SceneTree
## (a) 轻碎片是怎么拿到极高速度的？ (b) 灰尘策略在"切割 + 碎片堆积"场景里省多少？
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const Destruction := preload("res://src/core/destruction.gd")

func _shape(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _initialize() -> void:
	print("=== (a) 轻碎片被**夹**在重物与地面之间 ===")
	for frag in [2, 4, 8]:
		var w := PWorld.new()
		w.gravity = Vector2(0, 300)
		var g := PBody.new()
		g.make_static()
		w.add_body(g, [_shape(200, 40)])
		var dust := PBody.new()
		dust.position = Vector2(100, -6)
		w.add_body(dust, [_shape(frag, frag)])
		var heavy := PBody.new()
		heavy.position = Vector2(100, -80)
		w.add_body(heavy, [_shape(60, 60)])
		heavy.linear_velocity = Vector2(0, 1500)
		var vmax := 0.0
		for k in 60:
			w.step(1.0 / 60.0)
			vmax = maxf(vmax, dust.linear_velocity.length())
		print("  %dx%-2d 碎片（质量 %5.1f）被 60x60 重块以 1500 px/s 砸向地面 -> 峰值速度 %10.1f px/s | 当前子步 %d" % [
			frag, frag, dust.mass, vmax, w.last_substeps])

	print("")
	print("=== (b) 场景：切割地面 + 碎片堆积，最坏一帧 ===")
	for policy in [false, true]:
		var w2 := PWorld.new()
		w2.gravity = Vector2(0, 300)
		if policy:
			w2.debris_max_mass = 16.0
			w2.debris_min_speed = 2000.0
			w2.ccd_ignore_mass = 16.0
		var ground := PBody.new()
		ground.make_static()
		w2.add_body(ground, [_shape(768, 100)])
		var worst := 0.0
		var worst_frame := -1
		var total := 0.0
		var cut := 0
		for frame in 900:
			if frame % 20 == 0 and cut < 40:
				cut += 1
				var x := 40 + (cut * 17) % 700
				w2.fracture(ground, Destruction.Damage.segment(Vector2(x, -5), Vector2(x, 105), 3.0))
			if frame % 60 == 0:
				w2.cull_outside(Rect2(-600, -800, 1968, 1720))
				w2.enforce_body_budget()
			var t0 := Time.get_ticks_usec()
			w2.step(1.0 / 60.0)
			var ms := float(Time.get_ticks_usec() - t0) / 1000.0
			total += ms
			if ms > worst:
				worst = ms
				worst_frame = frame
		print("  策略 %s：最坏一帧 %8.3f ms（第 %d 帧）| 900 帧合计 %8.1f ms | 结束时刚体 %d | 子步 %d" % [
			"开" if policy else "关", worst, worst_frame, total, w2.bodies.size(), w2.last_substeps])
	quit(0)

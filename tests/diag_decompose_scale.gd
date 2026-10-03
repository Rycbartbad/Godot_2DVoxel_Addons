extends SceneTree
## rebuild 的 20 ms 到底在哪 —— 随矩形数增长看各段变化。
const AddonWorld := preload("res://src/nodes/pixel_world.gd")
const AddonBody := preload("res://src/nodes/pixel_body_2d.gd")
const AddonShape := preload("res://src/nodes/pixel_shape_2d.gd")
const GreedyRects := preload("res://src/core/greedy_rects.gd")
const Destruction := preload("res://src/core/destruction.gd")

func _initialize() -> void:
	var pw = AddonWorld.new()
	var g = AddonBody.new(); g.position = Vector2(0, 220); g.is_static = true
	pw.add_child(g)
	var gs = AddonShape.new(); gs.rect_size = Vector2i(768, 100); g.add_child(gs)
	get_root().add_child(pw)
	await process_frame
	await process_frame
	pw.rebuild()
	var b = null
	for x in pw.world.bodies:
		if x.is_static: b = x; break
	var s = b.shapes[0]

	print("=== decompose 随矩形数增长（单位 ms）===")
	print("擦除次数  矩形数   build_grid  greedy  merge   decompose")
	for i in 9:
		# 每轮挖 3 个洞，让矩形数涨上去
		for j in 3:
			var d = Destruction.Damage.circle(Vector2(40.0 + i * 80.0 + j * 20.0, 30.0 + j * 20.0), 6.0)
			Destruction.apply_damage(s, d)
		s.touch()
		var aabb = s.local_aabb()
		var g2 = GreedyRects._build_grid(s)
		var t0 := Time.get_ticks_usec()
		for q in 3:
			GreedyRects._build_grid(s)
		var t_grid := (Time.get_ticks_usec() - t0) / 3.0 / 1000.0
		t0 = Time.get_ticks_usec()
		var rects = GreedyRects._greedy(g2.words.duplicate(), g2.wq, g2.w, g2.h, true)
		var t_g := (Time.get_ticks_usec() - t0) / 1000.0
		t0 = Time.get_ticks_usec()
		GreedyRects._merge_pass(rects.duplicate())
		var t_m := (Time.get_ticks_usec() - t0) / 1000.0
		t0 = Time.get_ticks_usec()
		GreedyRects.decompose(s, 64)
		var t_d := (Time.get_ticks_usec() - t0) / 1000.0
		print("%6d  %6d  %9.2f  %6.2f  %5.2f  %8.2f" % [i + 1, rects.size(), t_grid, t_g, t_m, t_d])
	quit(0)

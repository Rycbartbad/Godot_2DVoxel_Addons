extends SceneTree
## 只读核查：增量网格路径到底有没有被命中？
## （如果没命中，第 7 轮那个缓存就白做了）
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

	print("=== 增量网格是否命中（单位 ms）===")
	print("情形                       build_grid  矩形数")
	# 1) 全量（touch，无块级脏信息）
	s.touch()
	var t := Time.get_ticks_usec()
	var g1 = GreedyRects._build_grid(s)
	var t_full := (Time.get_ticks_usec() - t) / 1000.0
	print("  全量（touch，无脏信息）      %8.2f  %5d" % [t_full, g1.w])

	# 2) 增量（mark_dirty_range，有块级脏信息）
	var d = Destruction.Damage.circle(Vector2(300, 50), 6.0)
	Destruction.apply_damage(s, d)
	var db: Rect2 = d.bounds()
	s.mark_dirty_range(Rect2i(int(db.position.x), int(db.position.y), int(db.size.x) + 1, int(db.size.y) + 1))
	t = Time.get_ticks_usec()
	var g2 = GreedyRects._build_grid(s)
	var t_inc := (Time.get_ticks_usec() - t) / 1000.0
	print("  增量（mark_dirty_range）     %8.2f  %5d" % [t_inc, g2.w])
	print("")
	print("  省了 %.1f 倍" % (t_full / maxf(t_inc, 0.001)))

	# 3) 真实擦除路径里 rebuild 的耗时（含 decompose）
	print("")
	print("=== 真实擦除里 rebuild 的耗时 ===")
	for i in 4:
		var wx := 100.0 + i * 120.0
		var d2 = Destruction.Damage.segment(Vector2(wx, 50), Vector2(wx, 51), 6.0)
		var db2: Rect2 = d2.bounds()
		Destruction.apply_damage(s, d2)
		t = Time.get_ticks_usec()
		b.rebuild([s], Callable(), 64, Rect2i(int(db2.position.x), int(db2.position.y), int(db2.size.x) + 1, int(db2.size.y) + 1))
		print("  笔画 %d  rebuild %7.2f ms  矩形数 %d" % [i, (Time.get_ticks_usec() - t) / 1000.0, b.rects.size()])
	quit(0)

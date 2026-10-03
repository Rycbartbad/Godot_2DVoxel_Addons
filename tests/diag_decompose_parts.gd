extends SceneTree
## decompose 分段计时 —— 不再猜。
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
	var s = null
	for b in pw.world.bodies:
		if b.is_static: s = b.shapes[0]; break

	# 打个洞 —— 实心快路径失效，走逐行拼接那条
	var d = Destruction.Damage.circle(Vector2(300, 50), 20.0)
	Destruction.apply_damage(s, d)
	s.touch()
	print("=== decompose 分段（有洞，单位 ms）px=%d aabb=%s ===" % [s.pixel_count(), str(s.local_aabb())])
	var N := 5
	var t := Time.get_ticks_usec()
	for i in N:
		GreedyRects._build_grid(s)
	var t_grid := (Time.get_ticks_usec() - t) / float(N) / 1000.0
	print("  _build_grid          %7.2f" % t_grid)

	var grid = GreedyRects._build_grid(s)
	t = Time.get_ticks_usec()
	for i in N:
		GreedyRects._greedy(grid.cells.duplicate(), grid.w, grid.h, true)
	var t_g1 := (Time.get_ticks_usec() - t) / float(N) / 1000.0
	print("  _greedy 横优先       %7.2f" % t_g1)

	var rects = GreedyRects._greedy(grid.cells.duplicate(), grid.w, grid.h, true)
	t = Time.get_ticks_usec()
	for i in N:
		GreedyRects._merge_pass(rects.duplicate())
	var t_m := (Time.get_ticks_usec() - t) / float(N) / 1000.0
	print("  _merge_pass（%d 矩形） %7.2f" % [rects.size(), t_m])

	t = Time.get_ticks_usec()
	for i in N:
		GreedyRects.decompose(s, 0)
	var t_all := (Time.get_ticks_usec() - t) / float(N) / 1000.0
	print("  decompose 整体       %7.2f" % t_all)
	print("")
	print("  未解释的部分 = %.2f ms" % (t_all - t_grid - t_m))
	quit(0)

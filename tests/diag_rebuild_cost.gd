extends SceneTree
## fracture 内部还剩什么 —— 直接量 body.rebuild（贪心矩形分解）。
const AddonWorld := preload("res://src/nodes/pixel_world.gd")
const AddonBody := preload("res://src/nodes/pixel_body_2d.gd")
const AddonShape := preload("res://src/nodes/pixel_shape_2d.gd")
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
	var ground = null
	for b in pw.world.bodies:
		if b.is_static: ground = b; break
	print("初始：%d 矩形" % ground.rects.size())

	# 1) rebuild 本身（形状没变）
	var t0 := Time.get_ticks_usec()
	for i in 5:
		ground.rebuild(ground.shapes, Callable(), 0)
	var per := (Time.get_ticks_usec() - t0) / 5.0 / 1000.0
	print("body.rebuild（形状没变）  = %.2f ms  -> %d 矩形" % [per, ground.rects.size()])

	# 2) 挖一下再 rebuild
	var d = Destruction.Damage.segment(Vector2(300, 50), Vector2(300, 51), 6.0)
	Destruction.apply_damage(ground.shapes[0], d)
	var t1 := Time.get_ticks_usec()
	ground.rebuild(ground.shapes, Callable(), 0)
	var per2 := (Time.get_ticks_usec() - t1) / 1000.0
	print("body.rebuild（挖过之后）  = %.2f ms  -> %d 矩形" % [per2, ground.rects.size()])

	# 3) 只做矩形分解，不含质量/物理推送 —— 用 max_rects 限制看变化
	var t2 := Time.get_ticks_usec()
	ground.rebuild(ground.shapes, Callable(), 4096)
	var per3 := (Time.get_ticks_usec() - t2) / 1000.0
	print("body.rebuild（上限 4096）  = %.2f ms  -> %d 矩形" % [per3, ground.rects.size()])
	print("")
	print("⚠️ 如果 rebuild 就是这个量级，那 fracture 的 48 ms 基本全是它。")
	quit(0)

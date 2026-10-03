extends SceneTree
## fracture 内部再分段 —— 增量缓存上了之后，大头是不是转移了？
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

	print("=== fracture 内部（单位 ms）===")
	print("笔画   gpu   touchB  apply   rebuild  合计")
	for i in 6:
		var wx := 80.0 + i * 90.0
		var wy := 270.0
		var d = Destruction.Damage.segment(
			ground.to_local(Vector2(wx, wy)), ground.to_local(Vector2(wx, wy + 1)), 6.0)
		var s = ground.shapes[0]
		var t0 := Time.get_ticks_usec()
		Destruction.apply_damage_and_split_gpu(s, d, 25.0)
		var t1 := Time.get_ticks_usec()
		var db: Rect2 = d.bounds()
		var probe := Rect2i(int(db.position.x) - 8, int(db.position.y) - 8,
			int(db.size.x) + 16, int(db.size.y) + 16)
		Destruction.touches_boundary(s, probe)
		var t2 := Time.get_ticks_usec()
		Destruction.apply_damage(s, d)
		var t3 := Time.get_ticks_usec()
		ground.rebuild([s], Callable(), 64, Rect2i(int(db.position.x), int(db.position.y), int(db.size.x) + 1, int(db.size.y) + 1))
		var t4 := Time.get_ticks_usec()
		print("%3d  %5.2f  %6.2f  %5.2f  %7.2f  %6.2f" % [
			i, (t1-t0)/1000.0, (t2-t1)/1000.0, (t3-t2)/1000.0, (t4-t3)/1000.0, (t4-t0)/1000.0])
	quit(0)

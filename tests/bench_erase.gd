extends SceneTree
## 擦除地面到底卡在哪：把每一笔拆成 擦除 / 同步地面 / 同步碎片 / step 四项。
## （之前那次把 sync 记成一个数，把地面和碎片混在一起了）
const AddonWorld := preload("res://src/nodes/pixel_world.gd")
const AddonBody := preload("res://src/nodes/pixel_body_2d.gd")
const AddonShape := preload("res://src/nodes/pixel_shape_2d.gd")
const Editor := preload("res://src/core/pixel_editor.gd")

func _initialize() -> void:
	print("=== 擦除地面：四项拆开（单位 ms）===")
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
	print("地面 %d px, %d 矩形" % [ground.shapes[0].pixel_count(), ground.rects.size()])
	print("")
	print("笔画  erase  sync地  sync碎  碎块数  step  矩形数  剩余px")
	for stroke in 10:
		var from := Vector2(60.0 + stroke * 40.0, 200.0)
		var to := Vector2(60.0 + stroke * 40.0, 260.0)
		var t0 := Time.get_ticks_usec()
		var res: Array = Editor.erase(pw.world, from, to, 6.0, 25.0)
		var t1 := Time.get_ticks_usec()
		var frag := 0
		for r in res:
			frag += r["spawned"].size()
		var t2 := Time.get_ticks_usec()
		for r in res:
			pw.renderer.sync(r["body"])
			for f in r["spawned"]:
				pw.renderer.sync(f)
		var t3 := Time.get_ticks_usec()
		pw.world.step(1.0 / 60.0)
		var t4 := Time.get_ticks_usec()
		print("%3d  %6.2f %6.2f %6.2f  %5d  %5.2f  %5d  %6d" % [
			stroke, (t1-t0)/1000.0, (t2-t1)/1000.0, (t3-t2)/1000.0,
			frag, (t4-t3)/1000.0, ground.rects.size(),
			ground.shapes[0].pixel_count()])
	quit(0)

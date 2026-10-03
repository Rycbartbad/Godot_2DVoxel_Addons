extends SceneTree
## **贴边界破坏**的常驻基准（用户报的场景：贴着边界挖小洞 / 沿边界拖一笔 / 一刀切断）。
##
## ⚠️ 为什么要有它：bench_erase_big / bench_erase_interior 量的都是**内部挖洞**，
##    那条路不跑连通性分裂。而"擦到边界"会跑 split —— 曾经是每笔 36~101 ms 的卡顿，
##    却没有任何常驻基准覆盖。这一支就是那次投诉留下的闸门。
##
## 2026-10 实测（768x100 地面，重复口径）：
##   内部小洞 r=4                2.25 ms/笔（对照：不跑 split）
##   贴边界小洞 r=4      16.6 -> **7.2 ms/笔**（局部连通判据，见 Destruction.local_connectivity）
##   沿边界拖一笔 90px  101.8 -> **16.2 ms/笔**
##   大半径切一刀 r=60    90.8 -> **36.3 ms/笔**（含生成碎片）
const AddonWorld := preload("res://src/nodes/pixel_world.gd")
const AddonBody := preload("res://src/nodes/pixel_body_2d.gd")
const AddonShape := preload("res://src/nodes/pixel_shape_2d.gd")
const Editor := preload("res://src/core/pixel_editor.gd")

func _mk(pw):
	var g = AddonBody.new()
	g.position = Vector2(0, 220)
	g.is_static = true
	pw.add_child(g)
	var gs = AddonShape.new()
	gs.rect_size = Vector2i(768, 100)
	g.add_child(gs)
	get_root().add_child(pw)
	await process_frame
	await process_frame
	pw.rebuild()

func _initialize() -> void:
	var pw = AddonWorld.new()
	await _mk(pw)
	var t := 0.0
	for i in 12:
		var from := Vector2(40.0 + i * 55.0, 270.0)
		var t0 := Time.get_ticks_usec()
		Editor.erase(pw.world, from, from + Vector2(0, 1), 4.0, 25.0)
		if i >= 2:
			t += (Time.get_ticks_usec() - t0) / 1000.0
	print("内部小洞（r=4，对照）          %6.2f ms/笔" % (t / 10.0))
	var pw2 = AddonWorld.new()
	await _mk(pw2)
	t = 0.0
	for i2 in 12:
		var f2 := Vector2(40.0 + i2 * 55.0, 221.0)
		var t1 := Time.get_ticks_usec()
		Editor.erase(pw2.world, f2, f2 + Vector2(0, 1), 4.0, 25.0)
		if i2 >= 2:
			t += (Time.get_ticks_usec() - t1) / 1000.0
	print("贴边界小洞（r=4）              %6.2f ms/笔" % (t / 10.0))
	var pw3 = AddonWorld.new()
	await _mk(pw3)
	t = 0.0
	for i3 in 6:
		var f3 := Vector2(60.0 + i3 * 100.0, 221.0)
		var t2 := Time.get_ticks_usec()
		Editor.erase(pw3.world, f3, f3 + Vector2(90, 0), 4.0, 25.0)
		if i3 >= 1:
			t += (Time.get_ticks_usec() - t2) / 1000.0
	print("沿边界拖一笔 90px              %6.2f ms/笔" % (t / 5.0))
	var pw4 = AddonWorld.new()
	await _mk(pw4)
	t = 0.0
	for i4 in 4:
		var f4 := Vector2(150.0 + i4 * 160.0, 270.0)
		var t3 := Time.get_ticks_usec()
		Editor.erase(pw4.world, f4, f4 + Vector2(0, 1), 60.0, 25.0)
		if i4 >= 1:
			t += (Time.get_ticks_usec() - t3) / 1000.0
	print("大半径切一刀（r=60，生成碎片）  %6.2f ms/笔" % (t / 3.0))
	quit(0)

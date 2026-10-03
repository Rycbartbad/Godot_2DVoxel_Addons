extends SceneTree
## 探针：AABB 缓存到底有没有被内部擦除保住？
const AddonWorld := preload("res://src/nodes/pixel_world.gd")
const AddonBody := preload("res://src/nodes/pixel_body_2d.gd")
const AddonShape := preload("res://src/nodes/pixel_shape_2d.gd")
const Editor := preload("res://src/core/pixel_editor.gd")

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
	var s = ground.shapes[0]
	s.local_aabb()
	var r0: int = s._aabb_rev
	var br0: int = s._bounds_rev
	print("预热后     _aabb_rev=%d _bounds_rev=%d 缓存有效=%s" % [r0, br0, r0 == br0])

	var t0 := Time.get_ticks_usec()
	for i in 10:
		var x := 60.0 + i * 60.0
		Editor.erase(pw.world, Vector2(x, 270.0), Vector2(x, 271.0), 6.0, 25.0)
	var dt := (Time.get_ticks_usec() - t0) / 10000.0
	var r1: int = ground.shapes[0]._aabb_rev
	var br1: int = ground.shapes[0]._bounds_rev
	print("内部擦10笔 %.2f ms/笔 | _aabb_rev %d->%d _bounds_rev %d->%d 命中=%s" % [
		dt, r0, r1, br0, br1, r0 == r1])

	var s2 = ground.shapes[0]
	s2.local_aabb()
	var b2: int = s2._bounds_rev
	Editor.erase(pw.world, Vector2(700.0, 221.0), Vector2(700.0, 222.0), 6.0, 25.0)
	var b3: int = ground.shapes[0]._bounds_rev
	print("贴边擦一笔 _bounds_rev %d->%d 作废=%s（必须为 true）" % [b2, b3, b2 != b3])
	quit(0)

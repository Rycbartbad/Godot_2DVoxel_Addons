extends SceneTree
## 验证：擦一笔之后，被标脏的块是不是**只有伤害覆盖的那一小片**。
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
	var sh = ground.shapes[0]
	var total_chunks: int = sh.chunks.size()
	print("地面 %d px | 总共 %d 个 chunk" % [sh.pixel_count(), total_chunks])
	print("")
	print("笔画  脏块数  占全部")
	for stroke in 6:
		# 每笔前清空脏集合，只看这一笔标了什么
		sh._dirty.clear()
		var from := Vector2(60.0 + stroke * 40.0, 200.0)
		var to := Vector2(60.0 + stroke * 40.0, 260.0)
		Editor.erase(pw.world, from, to, 6.0, 25.0)
		var n: int = sh._dirty.size()
		print("%3d   %5d   %5.1f%%" % [stroke, n, float(n) / float(total_chunks) * 100.0])
	print("")
	print("（如果 mark_dirty_range 没生效，这里会是 100% —— 整块都脏）")
	quit(0)

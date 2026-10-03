extends SceneTree
## 分块贴图到底有没有生效 —— 量"每笔重建了几块"。
##
## ⚠️ 这是"看起来对了"和"真的对了"的区别：
##    分块代码写完之后画面是对的，但完全可能每笔都走 rebuild_all，
##    那就等于没分块。只有计数器能证明。
const AddonWorld := preload("res://src/nodes/pixel_world.gd")
const AddonBody := preload("res://src/nodes/pixel_body_2d.gd")
const AddonShape := preload("res://src/nodes/pixel_shape_2d.gd")
const Editor := preload("res://src/core/pixel_editor.gd")

func _run(label: String, world_y: float) -> void:
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
	pw.renderer.sync(ground)
	print("  %s：首次全建 %d/%d 块" % [label,
		pw.renderer.last_tiles_rebuilt, pw.renderer.last_tiles_total])
	for i in 4:
		Editor.erase(pw.world, Vector2(80.0 + i * 120.0, world_y),
			Vector2(80.0 + i * 120.0, world_y + 1.0), 6.0, 25.0)
		pw.renderer.sync(ground)
		print("    笔画 %d -> 重建 %d/%d 块" % [i,
			pw.renderer.last_tiles_rebuilt, pw.renderer.last_tiles_total])

func _initialize() -> void:
	print("=== 分块贴图是否真的生效 ===")
	await _run("内部擦除", 270.0)
	await _run("边缘擦除", 205.0)
	quit(0)

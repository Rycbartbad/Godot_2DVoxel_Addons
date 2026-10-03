extends SceneTree
const AddonWorld := preload("res://src/nodes/pixel_world.gd")
const AddonBody := preload("res://src/nodes/pixel_body_2d.gd")
const AddonShape := preload("res://src/nodes/pixel_shape_2d.gd")

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
	pw.renderer.sync(ground)
	var tiles: Dictionary = pw.renderer._tiles.get(ground.id, {})
	print("块数=", tiles.size(), "  aabb=", ground.aabb, "  id=", ground.id)
	print("键=", tiles.keys())
	print("有 _tile_img 吗=", pw.renderer._tile_img.has(ground.id), " 源图数=", (pw.renderer._tile_img.get(ground.id, {}) as Dictionary).size())
	var k := Vector2i(200 >> 6, 250 >> 6)
	print("查找键=", k, " has=", tiles.has(k))
	print("tile_image_at=", pw.renderer.tile_image_at(ground.id, 200, 250))
	quit(0)

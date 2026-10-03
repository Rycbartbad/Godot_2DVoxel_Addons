extends SceneTree
## Profile Editor.erase 内部：GPU 路径到底走没走？
##
## 这是**最可疑的一点**：headless 没有 RenderingDevice，
## apply_damage_and_split_gpu 会返回空 -> 落到 CPU 回退。
## 那么我所有基准量的都是 CPU 路径，而真实游戏跑的是 GPU 路径 ——
## 如果真是这样，我的基准一直在量一个**游戏里不存在的成本**。
const AddonWorld := preload("res://src/nodes/pixel_world.gd")
const AddonBody := preload("res://src/nodes/pixel_body_2d.gd")
const AddonShape := preload("res://src/nodes/pixel_shape_2d.gd")
const Editor := preload("res://src/core/pixel_editor.gd")
const Destruction := preload("res://src/core/destruction.gd")

func _initialize() -> void:
	print("=== Editor.erase 内部 profile ===")
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

	# 1) GPU 路径可用吗？
	var d = Destruction.Damage.segment(Vector2(200, 30), Vector2(200, 31), 6.0)
	var t0 := Time.get_ticks_usec()
	var accel: Dictionary = Destruction.apply_damage_and_split_gpu(s, d, 25.0)
	var t_gpu := (Time.get_ticks_usec() - t0) / 1000.0
	print("  GPU 路径：返回空 = %s   耗时 %.2f ms" % [str(accel.is_empty()), t_gpu])
	print("  RenderingDevice 可用 = %s" % str(RenderingServer.get_rendering_device() != null))
	print("  渲染方式 = %s" % ProjectSettings.get_setting("rendering/renderer/rendering_method"))

	# 2) 逐块拆 CPU 路径
	var s2 = ground.shapes[0]
	var d2 = Destruction.Damage.segment(Vector2(400, 30), Vector2(400, 31), 6.0)
	var t1 := Time.get_ticks_usec()
	var removed: int = Destruction.apply_damage(s2, d2)
	var t_ad := (Time.get_ticks_usec() - t1) / 1000.0
	var t2 := Time.get_ticks_usec()
	var parts: Array = Destruction.split(s2, 25.0)
	var t_sp := (Time.get_ticks_usec() - t2) / 1000.0
	print("  CPU apply_damage = %.2f ms（removed=%d）" % [t_ad, removed])
	print("  CPU split        = %.2f ms（%d 块）" % [t_sp, parts.size()])

	# 3) 整体 erase 对照
	var t3 := Time.get_ticks_usec()
	Editor.erase(pw.world, Vector2(600, 250), Vector2(600, 251), 6.0, 25.0)
	var t_e := (Time.get_ticks_usec() - t3) / 1000.0
	print("  Editor.erase 整体 = %.2f ms" % t_e)
	print("")
	print("  ⚠️ 如果 GPU 返回空、且 apply_damage 占了大头，")
	print("     那我所有基准量的都是**游戏里不会走的 CPU 回退**。")
	quit(0)

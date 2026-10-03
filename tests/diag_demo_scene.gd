extends SceneTree
## 验证 demo 场景的关卡**确实由节点建出来了**（而不是靠 game.gd 生成）。
func _initialize() -> void:
	var ps := load("res://scenes/demo.tscn")
	if ps == null:
		print("FAIL 场景加载不了"); quit(1); return
	var root = ps.instantiate()
	get_root().add_child(root)
	await process_frame
	await process_frame
	var pw = root.get_node_or_null("PixelWorld")
	print("PixelWorld 节点: ", "有" if pw != null else "**没有**")
	if pw == null: quit(1); return
	print("world:  ", "有" if pw.world != null else "**没有**")
	print("renderer:", "有" if pw.renderer != null else "**没有**")
	if pw.world != null:
		var n: int = pw.world.bodies.size()
		var st: int = 0
		var dyn: int = 0
		for b in pw.world.bodies:
			if b.is_static: st += 1
			else: dyn += 1
		print("刚体 %d 个（静态 %d / 动态 %d）" % [n, st, dyn])
		for b in pw.world.bodies:
			print("   %-8s %s  pos=(%.0f, %.0f) rot=%.2f rects=%d" % [
				"静态" if b.is_static else "动态", str(b.shapes[0].pixel_count()) + "px",
				b.position.x, b.position.y, b.rotation, b.rects.size()])
	print("Camera2D: ", "有" if root.get_node_or_null("Camera2D") != null else "**没有**")
	print("UI/Hint:  ", "有" if root.get_node_or_null("UI/Hint") != null else "**没有**")
	print("DebugOverlay: ", "有" if root.get_node_or_null("PixelWorld/DebugOverlay") != null else "**没有**")
	quit(0)

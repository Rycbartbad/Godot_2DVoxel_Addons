extends SceneTree
## 渲染同步成本 vs 形状大小 —— 验证"地面是不是该切瓦片"。
const AddonWorld := preload("res://src/nodes/pixel_world.gd")
const AddonBody := preload("res://src/nodes/pixel_body_2d.gd")
const AddonShape := preload("res://src/nodes/pixel_shape_2d.gd")

func _measure(label: String, tiles: int) -> void:
	var pw = AddonWorld.new()
	# 铺一条 768x100 的地面，切成 tiles 块
	var tw := 768 / tiles
	for i in tiles:
		var b = AddonBody.new()
		b.position = Vector2(i * tw, 220)
		b.is_static = true
		pw.add_child(b)
		var s = AddonShape.new()
		s.rect_size = Vector2i(tw, 100)
		b.add_child(s)
	get_root().add_child(pw)
	await process_frame
	await process_frame
	pw.rebuild()

	# 只同步**其中一块**（模拟擦到它）
	var target = pw.world.bodies[0]
	var STEPS := 40
	var t0 := Time.get_ticks_usec()
	for i in STEPS:
		pw.renderer.sync(target)
	var per := (Time.get_ticks_usec() - t0) / float(STEPS) / 1000.0
	print("  %-22s %2d 块 | 单块 %4dx100 = %6d px | 同步一块 %7.2f ms" % [
		label, tiles, tw, tw * 100, per])
	pw.queue_free()
	await process_frame

func _initialize() -> void:
	print("=== 渲染同步成本 vs 瓦片大小（擦一次要重建的那块）===")
	await _measure("整块（我节点化时做的）", 1)
	await _measure("12 块", 12)
	await _measure("24 块", 24)
	await _measure("48 块", 48)
	quit(0)

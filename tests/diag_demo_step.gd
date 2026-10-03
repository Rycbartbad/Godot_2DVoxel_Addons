extends SceneTree
## 量 demo 场景里物体到底动没动 —— 判断"重力没了"是节点没推进，还是别的原因。
func _initialize() -> void:
	var root = load("res://scenes/demo.tscn").instantiate()
	get_root().add_child(root)
	await process_frame
	var pw = root.get_node("PixelWorld")
	print("auto_step = ", pw.auto_step, "   is_physics_processing = ", pw.is_physics_processing())
	print("world.gravity = ", pw.world.gravity, "   fixed_dt = ", pw.world.fixed_dt)
	var b = null
	for x in pw.world.bodies:
		if not x.is_static:
			b = x; break
	if b == null:
		print("**没有动态体**"); quit(0); return
	print("动态体初始 pos=", b.position)
	# 让它自己跑物理帧（不手动 step）—— 看节点有没有在推进
	for i in 30:
		await physics_frame
	print("等 30 个物理帧后 pos=", b.position, "  awake=", b.awake)
	# 再手动推 30 步对照
	for i in 30:
		pw.world.step(1.0 / 60.0)
	print("再手动推 30 步后 pos=", b.position)
	quit(0)

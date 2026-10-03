extends SceneTree
## 量重力：一个方块自由落体，看每步的速度增量是不是 g*dt。
## 双重推进的话这里会看到 2 倍。
func _initialize() -> void:
	var ps := load("res://scenes/demo.tscn")
	var root = ps.instantiate()
	get_root().add_child(root)
	await process_frame
	await process_frame
	var pw = root.get_node("PixelWorld")
	print("PixelWorld.auto_step = ", pw.auto_step, "   gravity = ", pw.world.gravity)
	# 直接手推世界（绕开节点与脚本，只量物理本身）
	var f = load("res://addons/pixel_destruction/pixel_physics.gd")
	print("（门面此刻不住在树里，跳过）")
	var b = null
	for x in pw.world.bodies:
		if not x.is_static:
			b = x
			break
	if b == null:
		print("没有动态体"); quit(0); return
	b.awake = true
	b.linear_velocity = Vector2.ZERO
	print("步   vy      每步增量（期望 g*dt = %.2f）" % (600.0 / 60.0))
	var prev := 0.0
	for i in 12:
		pw.world.step(1.0 / 60.0)
		var vy: float = b.linear_velocity.y
		print("%2d  %8.3f   %8.3f" % [i, vy, vy - prev])
		prev = vy
	quit(0)

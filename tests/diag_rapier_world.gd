extends SceneTree
## PWorld.use_rapier 模式的最小验证：一个方块落到地面上，应当停住并入睡。
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _initialize() -> void:
	print("=== PWorld.use_rapier 最小验证 ===")
	var w := PWorld.new()
	w.sleeping_enabled = true
	var g := PBody.new()
	g.position = Vector2(-200.0, 0.0)
	g.make_static()
	w.add_body(g, [_block(400, 40)])
	var b := PBody.new()
	b.position = Vector2(0.0, -100.0)
	w.add_body(b, [_block(16, 16)])
	print("地面 x∈[-200,200] 顶面 y=0；方块 16x16 从 y=-100 落下")
	print("方块静止时原点应在 y≈-16（底边贴 y=0）")
	for i in 120:
		w.step(1.0 / 60.0)
		if i % 20 == 0 or i == 119:
			print("  步 %3d  位置 (%9.3f, %9.3f)  rot=%9.5f  速度 (%8.3f, %8.3f)  awake=%s" % [
				i, b.position.x, b.position.y, b.rotation,
				b.linear_velocity.x, b.linear_velocity.y, str(b.awake)])
	print("")
	print("终态：原点 y=%.4f（底边 y=%.4f，期望 ≈0）" % [b.position.y, b.position.y + 16.0])
	print("      速度 (%.6f, %.6f)  ω=%.6f  awake=%s" % [
		b.linear_velocity.x, b.linear_velocity.y, b.angular_velocity, str(b.awake)])
	print("      rapier_id=%d  rects=%d  aabb=%s" % [b.rapier_id, b.rects.size(), str(b.aabb)])
	quit(0)

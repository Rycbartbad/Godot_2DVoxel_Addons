extends SceneTree
## 桥上有重物时，关节会不会被拉开？（静止自重 vs 砸下来一块金属）
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _rect(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _run(drop: bool) -> void:
	var world := PWorld.new()
	world.gravity = Vector2(0, 600)
	var ground := PBody.new()
	ground.position = Vector2(0, 220)
	ground.make_static()
	world.add_body(ground, [_rect(768, 100)])
	var planks := []
	for i in 4:
		var b := PBody.new()
		b.position = Vector2(306 + 31 * i, 98)
		world.add_body(b, [_rect(31, 6)])
		planks.append(b)
	world.add_hinge(null, planks[0], Vector2(306, 101))
	for i in 3:
		world.add_hinge(planks[i], planks[i + 1], Vector2(337 + 31 * i, 101))
	world.add_hinge(planks[3], null, Vector2(430, 101))
	if drop:
		var box := PBody.new()
		box.position = Vector2(360, 40)                 # 从桥上掉下来
		world.add_body(box, [_rect(24, 24)])
		box.mass = 0.0
		box.density = 7.8                               # 金属
		world.step(1.0 / 60.0)                          # 让密度生效
	var worst_gap := 0.0
	var worst_seam := 0.0
	for i in 600:
		world.step(1.0 / 60.0)
		for j in world.joints:
			worst_gap = maxf(worst_gap, j.anchor_a_world().distance_to(j.anchor_b_world()))
		for k in 3:
			var A = planks[k]
			var B = planks[k + 1]
			worst_seam = maxf(worst_seam, A.to_world(Vector2(31, 6)).distance_to(B.to_world(Vector2(0, 6))))
	print("%s  关节锚点最大间距 %.3f px   接缝最大张开 %.3f px" % ["砸重物" if drop else "只有自重", worst_gap, worst_seam])
	print("   桥板 y: %s" % str(planks.map(func(b): return "%.2f" % b.position.y)))

func _initialize() -> void:
	_run(false)
	_run(true)
	quit(0)
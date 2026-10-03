extends SceneTree
## 深穿透的伪速度挤出 vs 活过来的推测接触 —— 是不是在打架
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _run(name: String, slop: float, maxdep: float, start_y0: float = -7.0) -> void:
	var world := PWorld.new()
	world.sleeping_enabled = false
	world.solver.penetration_slop = slop
	world.solver.max_depenetration_speed = maxdep
	var g := PBody.new()
	g.position = Vector2(-600.0, 0.0)
	g.make_static()
	world.add_body(g, [_block(1200, 40)])
	var boxes: Array = []
	for p in 20:
		var gx := -560.0 + float(p) * 40.0
		for i in 4:
			var b := PBody.new()
			b.position = Vector2(gx, start_y0 - float(i) * 16.0)
			world.add_body(b, [_block(14, 14)])
			boxes.append(b)
	var maxsub := 0
	for step in 400:
		world.step(1.0 / 60.0)
		maxsub = maxi(maxsub, world.last_substeps)
	var worst := -1e18
	for b in boxes:
		worst = maxf(worst, b.aabb.end.y)
	print("  %-36s 最低底边 %10.2f  子步 %d  %s" % [name, worst, maxsub,
		"稳定" if worst < 3.0 else "塌陷"])

func _initialize() -> void:
	print("=== 扫 penetration_slop（原场景，初始嵌入 7px）===")
	for s in [0.5, 1.0, 2.0, 4.0, 8.0]:
		_run("slop=%.1f" % s, s, 100.0)
	print("=== 扫 max_depenetration_speed（slop=0.5）===")
	for d in [100.0, 50.0, 20.0, 5.0, 0.0]:
		_run("maxdepen=%.0f" % d, 0.5, d)
	print("=== 两个一起调 ===")
	_run("slop=2.0 maxdepen=20", 2.0, 20.0)
	_run("slop=4.0 maxdepen=20", 4.0, 20.0)
	quit(0)

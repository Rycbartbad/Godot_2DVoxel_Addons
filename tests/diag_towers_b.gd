extends SceneTree
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s
func _run(name: String, slop: float, maxdep: float, start_y0: float, steps: int = 400) -> void:
	var world := PWorld.new()
	world.sleeping_enabled = false
	world.use_threads = false
	world.use_native_solve = false
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
	for step in steps:
		world.step(1.0 / 60.0)
	var worst := -1e18
	for b in boxes:
		worst = maxf(worst, b.aabb.end.y)
	print("  %-40s 最低底边 %10.2f  %s" % [name, worst, "稳定" if worst < 3.0 else "塌陷"])
func _initialize() -> void:
	print("=== 重叠中心公式下，towers 场景 ===")
	_run("原样（slop=0.5 maxdepen=20 嵌入7px）", 0.5, 20.0, -7.0)
	_run("slop=2.0", 2.0, 20.0, -7.0)
	_run("slop=1.0", 1.0, 20.0, -7.0)
	_run("maxdepen=10", 0.5, 10.0, -7.0)
	_run("maxdepen=40", 0.5, 40.0, -7.0)
	_run("嵌入 0px", 0.5, 20.0, -14.0)
	_run("嵌入 2px", 0.5, 20.0, -12.0)
	quit(0)

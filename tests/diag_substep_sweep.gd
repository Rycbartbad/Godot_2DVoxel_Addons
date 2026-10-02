extends SceneTree
## 子步数扫描：找出塌陷的临界点
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _run(motion: float, steps: int = 400) -> void:
	var world := PWorld.new()
	world.sleeping_enabled = false
	world.use_threads = false
	world.use_native_solve = false
	world.ccd_max_motion = motion
	var g := PBody.new()
	g.position = Vector2(-600.0, 0.0)
	g.make_static()
	world.add_body(g, [_block(1200, 40)])
	var boxes: Array = []
	for p in 20:
		var gx := -560.0 + float(p) * 40.0
		for i in 4:
			var b := PBody.new()
			b.position = Vector2(gx, -7.0 - float(i) * 16.0)
			world.add_body(b, [_block(14, 14)])
			boxes.append(b)
	var maxsub := 0
	for step in steps:
		world.step(1.0 / 60.0)
		maxsub = maxi(maxsub, world.last_substeps)
	var worst := -1e18
	for b in boxes:
		worst = maxf(worst, b.aabb.end.y)
	print("  ccd_max_motion=%5.2f -> 子步峰值 %d  最低底边 %10.2f  %s" % [
		motion, maxsub, worst, "稳定" if worst < 3.0 else "塌陷"])

func _initialize() -> void:
	print("=== 子步数 vs 稳定性 ===")
	for m in [8.0, 6.0, 5.0, 4.0, 3.0, 2.5, 2.0, 1.5, 1.0]:
		_run(m)
	quit(0)

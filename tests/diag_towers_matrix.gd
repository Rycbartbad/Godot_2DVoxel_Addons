extends SceneTree
## 矩阵：towers 场景的塌陷由什么决定
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _run(name: String, threads: bool, native: bool, ccd: bool, steps: int = 400) -> void:
	var world := PWorld.new()
	world.sleeping_enabled = false
	world.use_threads = threads
	world.ccd_enabled = ccd
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
	for step in steps:
		world.step(1.0 / 60.0)
	var worst := -1e18
	for b in boxes:
		worst = maxf(worst, b.aabb.end.y)
	print("  %-32s 最低底边 %10.2f   %s" % [name, worst,
		"稳定" if worst < 3.0 else "塌陷"])

func _initialize() -> void:
	print("=== towers 场景矩阵（地面顶 y=0）===")
	_run("threads=on  native=off", true, false, true)
	_run("threads=off native=off", false, false, true)
	_run("threads=on  native=on", true, true, true)
	_run("threads=off native=on", false, true, true)
	print("=== 关掉 CCD 看它是不是在兜底 ===")
	_run("threads=off native=off ccd=off", false, false, false)
	_run("threads=off native=on  ccd=off", false, true, false)
	quit(0)

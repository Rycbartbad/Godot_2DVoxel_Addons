extends SceneTree
## 初始条件 vs 稳定性：towers 场景原本初始就陷进地面 7px
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

## start_y0 = 最底层箱子的 y。原场景是 -7（底边 +7，陷进地面 7px）
## 正确值是 -14（底边正好在 0）
func _run(name: String, start_y0: float, gap: float, steps: int = 400) -> void:
	var world := PWorld.new()
	world.sleeping_enabled = false
	world.use_threads = false
	var g := PBody.new()
	g.position = Vector2(-600.0, 0.0)
	g.make_static()
	world.add_body(g, [_block(1200, 40)])
	var boxes: Array = []
	for p in 20:
		var gx := -560.0 + float(p) * 40.0
		for i in 4:
			var b := PBody.new()
			b.position = Vector2(gx, start_y0 - float(i) * (14.0 + gap))
			world.add_body(b, [_block(14, 14)])
			boxes.append(b)
	var maxsub := 0
	for step in steps:
		world.step(1.0 / 60.0)
		maxsub = maxi(maxsub, world.last_substeps)
	var worst := -1e18
	for b in boxes:
		worst = maxf(worst, b.aabb.end.y)
	print("  %-38s 最低底边 %10.2f  子步 %d  %s" % [name, worst, maxsub,
		"稳定" if worst < 3.0 else "塌陷"])

func _initialize() -> void:
	print("=== 初始嵌入深度的影响（towers，20 塔 x 4 层）===")
	_run("原场景：初始嵌入 7px", -7.0, 2.0)
	_run("初始嵌入 0（底边正好贴地）", -14.0, 2.0)
	_run("初始嵌入 1px", -13.0, 2.0)
	_run("初始嵌入 2px", -12.0, 2.0)
	_run("初始嵌入 4px", -10.0, 2.0)
	_run("贴地且无间隙", -14.0, 0.0)
	quit(0)

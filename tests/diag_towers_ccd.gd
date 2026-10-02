extends SceneTree
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _run(name: String, cfg: Dictionary, steps: int = 400) -> void:
	var world := PWorld.new()
	world.sleeping_enabled = false
	world.use_threads = false
	world.use_native_solve = false
	for k in cfg:
		world.set(k, cfg[k])
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
	var clamped := 0
	var maxsub := 0
	for step in steps:
		world.step(1.0 / 60.0)
		maxsub = maxi(maxsub, world.last_substeps)
	var worst := -1e18
	for b in boxes:
		worst = maxf(worst, b.aabb.end.y)
	print("  %-40s 最低底边 %10.2f  子步峰值 %d  %s" % [name, worst, maxsub,
		"稳定" if worst < 3.0 else "塌陷"])

func _initialize() -> void:
	print("=== 拆解 CCD 的两条机制 ===")
	_run("ccd 全开（默认）", {"ccd_enabled": true})
	_run("ccd_enabled=false", {"ccd_enabled": false})
	_run("只关位移硬钳", {"ccd_enabled": true, "ccd_clamp_motion": false})
	_run("只关自动扫掠（保留硬钳）", {"ccd_enabled": true, "ccd_auto": false})
	_run("两条都关", {"ccd_enabled": true, "ccd_auto": false, "ccd_clamp_motion": false})
	_run("硬钳放宽到 4.0", {"ccd_enabled": true, "ccd_max_motion": 4.0})
	_run("硬钳放宽到 8.0", {"ccd_enabled": true, "ccd_max_motion": 8.0})
	quit(0)

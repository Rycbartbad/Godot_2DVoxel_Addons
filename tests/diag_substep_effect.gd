extends SceneTree
## 判定：到底是"子步细分"还是"CCD"导致撞墙反弹
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _block(w: int, h: int, mat: int = 1) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, mat)
	return s

func _run(speed: float, cfg: String) -> Dictionary:
	var w := PWorld.new()
	w.gravity = Vector2.ZERO
	match cfg:
		"默认": pass
		"无CCD": w.ccd_enabled = false
		"1子步": w.ccd_max_substeps = 1; w.ccd_clamp_motion = false
		"细2x": w.ccd_max_motion = 1.0
		"细4x": w.ccd_max_motion = 0.5
		"细8x": w.ccd_max_motion = 0.25
		"预算大": w.ccd_substep_budget = 100000
	var wall := PBody.new()
	wall.position = Vector2(200, 0)
	wall.make_static()
	w.add_body(wall, [_block(8, 200)])
	var b := PBody.new()
	b.position = Vector2(50, 100)
	w.add_body(b, [_block(12, 12)])
	b.linear_velocity = Vector2(speed, 0)
	var maxsub := 0
	for i in 120:
		w.step(1.0 / 60.0)
		maxsub = maxi(maxsub, w.last_substeps)
	return {"x": b.position.x, "sub": maxsub}

func _initialize() -> void:
	print("理想静止 x≈188；列 = 每步的最大子步数")
	print("%8s | %10s %10s %10s %10s %10s %10s %10s" % ["速度", "默认", "无CCD", "1子步", "细2x", "细4x", "细8x", "预算大"])
	for speed in [600.0, 1500.0, 3000.0]:
		var cells: Array = []
		for cfg in ["默认", "无CCD", "1子步", "细2x", "细4x", "细8x", "预算大"]:
			var r := _run(speed, cfg)
			cells.append("%8.1f/%2d" % [r["x"], r["sub"]])
		print("%8.0f | %s" % [speed, " ".join(cells)])
	quit(0)

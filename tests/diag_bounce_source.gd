extends SceneTree
## 反弹的来源判定：位移硬钳 / 穿透修正 / 迭代次数
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
		"无挤出": w.solver.max_depenetration_speed = 0.0
		"挤出1": w.solver.max_depenetration_speed = 1.0
		"无slop": w.solver.penetration_slop = 0.0
		"少迭代": w.solver.iterations = 4
		"无位移钳": w.ccd_clamp_motion = false
	var wall := PBody.new()
	wall.position = Vector2(200, 0)
	wall.make_static()
	w.add_body(wall, [_block(8, 200)])
	var b := PBody.new()
	b.position = Vector2(50, 100)
	w.add_body(b, [_block(12, 12)])
	b.linear_velocity = Vector2(speed, 0)
	for i in 120:
		w.step(1.0 / 60.0)
	return {"x": b.position.x, "rot": b.rotation}

func _initialize() -> void:
	print("理想静止 x≈188，rot≈0")
	print("%8s | %s" % ["速度", "默认            无挤出          挤出1           无slop          少迭代          无位移钳"])
	for speed in [600.0, 1500.0, 3000.0]:
		var cells: Array = []
		for cfg in ["默认", "无挤出", "挤出1", "无slop", "少迭代", "无位移钳"]:
			var r := _run(speed, cfg)
			cells.append("%8.2f/%6.3f" % [r["x"], r["rot"]])
		print("%8.0f | %s" % [speed, " ".join(cells)])
	quit(0)

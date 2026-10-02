extends SceneTree
## 高速撞墙：精确 OBB sweep（b.ccd = true）能不能治好"反弹"缺陷
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _block(w: int, h: int, mat: int = 1) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, mat)
	return s

func _run(speed: float, use_ccd: bool) -> Dictionary:
	var world := PWorld.new()
	world.gravity = Vector2.ZERO
	var wall := PBody.new()
	wall.position = Vector2(200, 0)
	wall.make_static()
	world.add_body(wall, [_block(8, 200)])
	var b := PBody.new()
	b.position = Vector2(50, 100)
	b.ccd = use_ccd
	world.add_body(b, [_block(12, 12)])
	b.linear_velocity = Vector2(speed, 0)
	var worst_pen := -1.0e9
	for i in 120:
		world.step(1.0 / 60.0)
		worst_pen = maxf(worst_pen, (b.position.x + 12.0) - 200.0)
	return {"x": b.position.x, "pen": worst_pen, "sub": world.last_substeps}

func _initialize() -> void:
	print("墙左沿 x=200，箱宽 12 -> 理想静止 x≈188")
	print("%8s | %10s %10s | %10s %10s | 最大嵌入(关/开)" % ["速度", "x(关)", "x(开)", "子步(关)", "子步(开)"])
	for speed in [600.0, 1500.0, 3000.0, 6000.0, 12000.0]:
		var off := _run(speed, false)
		var on := _run(speed, true)
		print("%8.0f | %10.2f %10.2f | %10d %10d | %6.2f / %6.2f" % [
			speed, off["x"], on["x"], off["sub"], on["sub"], off["pen"], on["pen"]])
	quit(0)

extends SceneTree
## 边际扫描：撞墙结果 vs 休眠，找转折点
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _block(w: int, h: int, mat: int = 1) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, mat)
	return s

func _tunnel(margin: float, speed: float) -> Dictionary:
	var w := PWorld.new()
	w.gravity = Vector2.ZERO
	w.max_speculative_margin = margin
	var wall := PBody.new()
	wall.position = Vector2(200, 0)
	wall.make_static()
	w.add_body(wall, [_block(8, 200)])
	var b := PBody.new()
	b.position = Vector2(50, 100)
	w.add_body(b, [_block(12, 12)])
	b.linear_velocity = Vector2(speed, 0)
	var maxv := 0.0
	for i in 120:
		w.step(1.0 / 60.0)
		maxv = maxf(maxv, absf(b.angular_velocity))
	return {"x": b.position.x, "rot": b.rotation, "wmax": maxv}

func _sleep(margin: float) -> String:
	var w := PWorld.new()
	w.max_speculative_margin = margin
	var g := PBody.new()
	g.position = Vector2(-2000.0, 0.0)
	g.make_static()
	w.add_body(g, [_block(4000, 40)])
	for i2 in 12:
		var b := PBody.new()
		b.position = Vector2(-100.0 + float(i2 % 4) * 18.0, -9.0 - float(i2 / 4) * 18.0)
		w.add_body(b, [_block(16, 16)])
	for i in 600:
		w.step(1.0 / 60.0)
	var awake := 0
	for b in w.bodies:
		if b.is_static:
			continue
		if b.awake:
			awake += 1
	return "%d/12" % awake

func _initialize() -> void:
	print("理想撞墙 x≈188 rot≈0；wmax 是整个过程里最大角速度")
	print("%6s | %9s %9s %9s | %9s %9s %9s | %8s" % [
		"边际", "x@600", "rot@600", "wmax@600", "x@1500", "rot@1500", "wmax@1500", "休眠"])
	for margin in [0.0, 0.1, 0.5, 1.0, 1.5, 2.0, 3.0, 5.0]:
		var a := _tunnel(margin, 600.0)
		var b := _tunnel(margin, 1500.0)
		print("%6.1f | %9.2f %9.3f %9.2f | %9.2f %9.3f %9.2f | %8s" % [
			margin, a["x"], a["rot"], a["wmax"], b["x"], b["rot"], b["wmax"], _sleep(margin)])
	quit(0)

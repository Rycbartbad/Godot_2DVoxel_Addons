extends SceneTree
## 推测接触是不是 600/1500 反弹的触发器？
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _block(w: int, h: int, mat: int = 1) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, mat)
	return s

func _run(speed: float, margin: float, x0: float) -> Dictionary:
	var w := PWorld.new()
	w.gravity = Vector2.ZERO
	w.max_speculative_margin = margin
	var wall := PBody.new()
	wall.position = Vector2(200, 0)
	wall.make_static()
	w.add_body(wall, [_block(8, 200)])
	var b := PBody.new()
	b.position = Vector2(x0, 100)
	w.add_body(b, [_block(12, 12)])
	b.linear_velocity = Vector2(speed, 0)
	for i in 120:
		w.step(1.0 / 60.0)
	return {"x": b.position.x, "rot": b.rotation}

func _initialize() -> void:
	print("理想 x≈188 rot≈0；边际 0 = 完全关闭推测接触")
	print("%8s | %14s %14s %14s %14s" % ["速度", "边际2(默认)@x50", "边际0@x50", "边际0.1@x50", "边际2@x170"])
	for speed in [600.0, 1500.0, 3000.0]:
		var a := _run(speed, 2.0, 50.0)
		var c := _run(speed, 0.0, 50.0)
		var d := _run(speed, 0.1, 50.0)
		var e := _run(speed, 2.0, 170.0)
		print("%8.0f | %8.2f/%5.2f %8.2f/%5.2f %8.2f/%5.2f %8.2f/%5.2f" % [
			speed, a["x"], a["rot"], c["x"], c["rot"], d["x"], d["rot"], e["x"], e["rot"]])
	quit(0)

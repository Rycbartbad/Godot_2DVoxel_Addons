extends SceneTree
## 责任划分：撞墙反弹到底来自 CCD，还是来自子步/求解路径？
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _block(w: int, h: int, mat: int = 1) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, mat)
	return s

func _run(speed: float, mode: String) -> Dictionary:
	var world := PWorld.new()
	world.gravity = Vector2.ZERO
	match mode:
		"ccd_off":
			world.ccd_enabled = false
		"auto_off":
			world.ccd_auto = false
		"forced":
			world.ccd_auto = false
		"maxsub1":
			world.ccd_max_substeps = 1     # 完全不做子步细分
	var wall := PBody.new()
	wall.position = Vector2(200, 0)
	wall.make_static()
	world.add_body(wall, [_block(8, 200)])
	var b := PBody.new()
	b.position = Vector2(50, 100)
	b.ccd = (mode == "forced")
	world.add_body(b, [_block(12, 12)])
	b.linear_velocity = Vector2(speed, 0)
	for i in 120:
		world.step(1.0 / 60.0)
	return {"x": b.position.x}

func _initialize() -> void:
	print("墙左沿 200，箱宽 12 -> 理想静止 188；>208 表示穿过去")
	print("%8s | %10s %10s %10s %10s" % ["速度", "CCD全关", "仅关自动", "强制CCD", "只1子步"])
	for speed in [600.0, 1500.0, 3000.0, 6000.0]:
		var a := _run(speed, "ccd_off")
		var c := _run(speed, "auto_off")
		var d := _run(speed, "forced")
		var e := _run(speed, "maxsub1")
		print("%8.0f | %10.2f %10.2f %10.2f %10.2f" % [
			speed, a["x"], c["x"], d["x"], e["x"]])
	quit(0)

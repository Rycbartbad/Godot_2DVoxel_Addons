extends SceneTree
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

func _drop(grav: float, term: float, drop_h: float, label: String) -> void:
	var world := PWorld.new()
	world.gravity = Vector2(0, grav)
	world.terminal_speed = term
	var b := PBody.new()
	b.position = Vector2(0, 0)
	world.add_body(b, [_block(14, 14)])
	var t := 0.0
	var hit_v := 0.0
	for i in 600:
		world.step(1.0 / 60.0)
		t += 1.0 / 60.0
		if b.position.y >= drop_h:
			hit_v = b.linear_velocity.y
			break
		hit_v = b.linear_velocity.y
	print("  %-28s 落 %.0f 单位用 %5.2f s | 落地速度 %6.1f 单位/s (= %.0f 屏幕像素/s @3x)" % [
		label, drop_h, t, hit_v, hit_v * 3.0])

func _initialize() -> void:
	print("=== 下落手感（可见高度 = 180 世界单位 @ 缩放 3）===")
	_drop(900.0, 0.0, 208.0, "旧 (g=900, 无终端速度)")
	_drop(600.0, 650.0, 208.0, "新 (g=600, 终端 650)")
	print("\n  长距离下落 3000 单位：")
	_drop(900.0, 0.0, 3000.0, "旧")
	_drop(600.0, 650.0, 3000.0, "新")
	quit(0)

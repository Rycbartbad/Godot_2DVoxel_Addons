extends SceneTree
## 探针：关节冲量到底有没有被 Rapier 写回？（rb_joint_impulse）
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _shape(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

func _initialize() -> void:
	var world := PWorld.new()
	var b := PBody.new()
	b.position = Vector2(100, 100)
	world.add_body(b, [_shape(16, 16)])
	var j = world.add_hinge(b, null, Vector2(100, 100))
	j.break_impulse = 1.0e12     # 只是为了让每子步都读冲量（不断）
	for i in 40:
		world.step(1.0 / 60.0)
		if i % 5 == 0 or i < 3:
			print("step %2d  awake=%s  pos=(%.1f, %.1f)  rot=%.3f  lin=%.3f  ang=%.3f  movement=%.3f" % [
				i, str(b.awake), b.position.x, b.position.y, b.rotation,
				j.last_linear_impulse, j.last_angular_impulse, j.movement()])
	# 滑轨：竖直载荷（线性冲量）
	var w2 := PWorld.new()
	var b2 := PBody.new()
	b2.position = Vector2(100, 100)
	w2.add_body(b2, [_shape(16, 16)])
	var j2 = w2.add_slider(b2, null, Vector2(100, 100), Vector2.RIGHT)
	j2.break_impulse = 1.0e12
	for i in 20:
		w2.step(1.0 / 60.0)
	print("slider: awake=%s  y=%.1f  lin=%.3f  ang=%.3f" % [
		str(b2.awake), b2.position.y, j2.last_linear_impulse, j2.last_angular_impulse])
	quit(0)

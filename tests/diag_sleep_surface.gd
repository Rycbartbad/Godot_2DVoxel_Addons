extends SceneTree
## 残余抖动：vmax 2.47 已低于 sleep_linear=6.0 却睡不着，查是不是 sleep_surface 卡的
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _run(surf: float, gap: float, steps: int = 300) -> void:
	var w := PWorld.new()
	w.sleep_surface = surf
	var g := PBody.new()
	g.position = Vector2(-300.0, 400.0)
	g.make_static()
	w.add_body(g, [_block(600, 40)])
	var boxes: Array = []
	for i in 3:
		var b := PBody.new()
		b.position = Vector2(0.0, 400.0 - 20.0 * (i + 1) - gap * (i + 1))
		w.add_body(b, [_block(20, 20)])
		boxes.append(b)
	for step in steps:
		w.step(1.0 / 60.0)
	var awake := 0
	for b in boxes:
		if b.awake:
			awake += 1
	var vmax := 0.0
	var wmax := 0.0
	for b in boxes:
		vmax = maxf(vmax, absf(b.linear_velocity.y))
		wmax = maxf(wmax, absf(b.angular_velocity))
	print("  sleep_surface=%5.1f gap=%.0f -> vmax %6.3f  wmax %6.4f  清醒 %d/3  %s" % [
		surf, gap, vmax, wmax, awake, "睡着 ✓" if awake == 0 else "仍在抖"])

func _initialize() -> void:
	print("=== 残余抖动 vs sleep_surface ===")
	for s in [6.0, 9.0, 12.0, 16.0]:
		_run(s, 4.0)
	print("=== gap=8 ===")
	for s in [6.0, 12.0, 16.0]:
		_run(s, 8.0)
	quit(0)

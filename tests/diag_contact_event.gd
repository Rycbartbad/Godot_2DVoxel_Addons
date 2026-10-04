extends SceneTree
## 验证消费侧：Contact 现在是**多点**的（op 35 驱动），并且新增字段不影响旧字段。
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _box(w: int, h: int, mat: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), mat)
	return s

func _initialize() -> void:
	var w := PWorld.new()
	w.gravity = Vector2(0, 600)
	w.contact_events_enabled = true
	var ground := PBody.new()
	ground.position = Vector2(0, 100)
	ground.make_static()
	w.add_body(ground, [_box(200, 8, 1)], Callable(), true)
	var box := PBody.new()
	box.position = Vector2(50, 84)
	w.add_body(box, [_box(32, 8, 2)], Callable(), true)
	w._rp_ensure()
	var best := 0
	for i in 90:
		w.step(1.0 / 60.0)
		for c in w.contacts:
			if c.points.size() > best:
				best = c.points.size()
				print("第 %d 帧：Contact.points = %d 个" % [i, c.points.size()])
				for p in c.points:
					print("    pos=(%.2f,%.2f) dist=%.3f 冲量=%.4f" % [p["position"].x, p["position"].y, p["dist"], p["impulse"]])
				print("  impulse=%.4f total_impulse=%.4f width=%.3f depth=%.4f area=%.4f approach=%.3f" % [
					c.impulse, c.total_impulse, c.width, c.depth, c.area, c.approach])
	print("最大点数 = %d" % best)
	quit(0)

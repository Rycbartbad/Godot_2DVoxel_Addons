extends SceneTree
## 追踪"留 8px 间隙"这个失稳案例
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _initialize() -> void:
	var w := PWorld.new()
	var g := PBody.new()
	g.position = Vector2(-300.0, 400.0)
	g.make_static()
	w.add_body(g, [_block(600, 40)])
	var boxes: Array = []
	for i in 3:
		var b := PBody.new()
		b.position = Vector2(0.0, 400.0 - 20.0 * (i + 1) - 8.0 * (i + 1))
		w.add_body(b, [_block(20, 20)])
		boxes.append(b)
	print("步   方块0.y     v0      方块1.y     v1      方块2.y     v2      子步 清醒")
	for step in 300:
		w.step(1.0 / 60.0)
		if step < 40 or step % 20 == 0:
			var awake := 0
			for b in boxes:
				if b.awake:
					awake += 1
			print("%3d %9.4f %8.2f %9.4f %8.2f %9.4f %8.2f  %d  %d/3" % [
				step, boxes[0].position.y, boxes[0].linear_velocity.y,
				boxes[1].position.y, boxes[1].linear_velocity.y,
				boxes[2].position.y, boxes[2].linear_velocity.y,
				w.last_substeps, awake])
	print("=== 末态 ===")
	for i in 3:
		print("  方块%d: y=%.6f rot=%.6f v=%.4f w=%.4f 睡着=%s" % [
			i, boxes[i].position.y, boxes[i].rotation,
			boxes[i].linear_velocity.y, boxes[i].angular_velocity, not boxes[i].awake])
	quit(0)

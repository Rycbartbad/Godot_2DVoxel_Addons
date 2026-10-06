extends SceneTree
## 撞击那一刻，接触查询路径到底给出什么？（demo 的撞击破坏靠它）
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _shape(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _initialize() -> void:
	var w := PWorld.new()
	w.gravity = Vector2(0, 300)
	var ground := PBody.new()
	ground.make_static()
	w.add_body(ground, [_shape(400, 40)])
	var block := PBody.new()
	block.position = Vector2(200, -60)
	w.add_body(block, [_shape(40, 40)])
	block.linear_velocity = Vector2(0, 900)
	print("=== 落块撞击：contact_pair_count / total_impulse ===")
	for frame in 60:
		w.step(1.0 / 60.0)
		var n: int = w.contact_pair_count()
		var line := "  帧 %2d | 对 %d | 块 vy %9.1f" % [frame, n, block.linear_velocity.y]
		for i in mini(n, 3):
			var info: Dictionary = w.contact_info(i)
			line += " | [%d] a=%d b=%d imp=%12.1f pts=%d" % [
				i, int(info["id_a"]), int(info["id_b"]),
				float(info["total_impulse"]), (info["points"] as Array).size()]
		print(line)
	quit(0)

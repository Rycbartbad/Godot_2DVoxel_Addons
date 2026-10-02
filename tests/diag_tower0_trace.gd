extends SceneTree
## 追踪塔0顶层箱子在子步=6 时的逐步状态
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _initialize() -> void:
	var world := PWorld.new()
	world.sleeping_enabled = false
	world.use_threads = false
	world.use_native_solve = false
	world.ccd_max_motion = 2.0
	var g := PBody.new()
	g.position = Vector2(-600.0, 0.0)
	g.make_static()
	world.add_body(g, [_block(1200, 40)])
	var boxes: Array = []
	for p in 20:
		var gx := -560.0 + float(p) * 40.0
		for i in 4:
			var b := PBody.new()
			b.position = Vector2(gx, -7.0 - float(i) * 16.0)
			world.add_body(b, [_block(14, 14)])
			boxes.append(b)
	# 塔0 的 4 层：索引 0..3
	var t0: Array = [boxes[0], boxes[1], boxes[2], boxes[3]]
	print("步  层3.y     层3.vy    层2.y     层2.vy    层1.y     层0.y    子步")
	for step in 145:
		world.step(1.0 / 60.0)
		if step >= 100 and step <= 140:
			print("%3d %9.3f %8.2f %9.3f %8.2f %9.3f %9.3f   %d" % [
				step, t0[3].position.y, t0[3].linear_velocity.y,
				t0[2].position.y, t0[2].linear_velocity.y,
				t0[1].position.y, t0[0].position.y, world.last_substeps])
	quit(0)

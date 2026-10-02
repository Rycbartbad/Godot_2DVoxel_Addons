extends SceneTree
## 诊断：三个方块叠在一起抖动
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
	g.position = Vector2(-200.0, 400.0)
	g.make_static()
	w.add_body(g, [_block(400, 40)])

	var boxes: Array = []
	for i in 3:
		var b := PBody.new()
		# 从地面往上叠：方块 20x20，地面顶 y=400
		b.position = Vector2(0.0, 380.0 - i * 20.0)
		w.add_body(b, [_block(20, 20)])
		boxes.append(b)

	print("=== 静置 180 步，看后 60 步的抖动 ===")
	print("步      方块0.y      方块1.y      方块2.y     清醒")
	var hist: Array = []
	for step in 180:
		w.step(1.0 / 60.0)
		if step >= 120:
			hist.append([boxes[0].position.y, boxes[1].position.y, boxes[2].position.y])
		if step % 30 == 0 or step >= 176:
			var awake := 0
			for b in boxes:
				if b.awake:
					awake += 1
			print("%4d  %10.6f  %10.6f  %10.6f   %d/3" % [
				step, boxes[0].position.y, boxes[1].position.y, boxes[2].position.y, awake])

	# 抖动 = 后 60 步里 y 的极差
	print("=== 后 60 步的极差（越小越稳）===")
	for i in 3:
		var lo := 1e9
		var hi := -1e9
		for h in hist:
			lo = minf(lo, h[i])
			hi = maxf(hi, h[i])
		print("  方块%d: 极差 %.6f px   (%.6f ~ %.6f)" % [i, hi - lo, lo, hi])

	# 相对速度的抖动
	print("=== 末步速度 ===")
	for i in 3:
		print("  方块%d: v=%.6f w=%.6f" % [i, boxes[i].linear_velocity.y, boxes[i].angular_velocity])
	quit(0)

extends SceneTree
## 复现：拖动一个物体，被旁边休眠的物体挡住
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _block(w: int, h: int, mat: int = 1) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, mat)
	return s

func _run(drag_speed: float) -> void:
	var w := PWorld.new()
	var g := PBody.new()
	g.position = Vector2(-300.0, 300.0)
	g.make_static()
	w.add_body(g, [_block(600, 40)])
	var boxes: Array = []
	for i in 3:
		var b := PBody.new()
		b.position = Vector2(-60.0 + float(i) * 24.0, 280.0)
		w.add_body(b, [_block(24, 24)])
		boxes.append(b)
	# 先让它们睡着
	for i in 240:
		w.step(1.0 / 60.0)
	var awake0 := 0
	for b in boxes:
		if b.awake:
			awake0 += 1
	# 抓住最左边那个，向右手边拖（B 方向为 +x）
	var a: PBody = boxes[0]
	var x0 := a.position.x
	w.grab(a, a.com_world(), 4000.0)
	var moved := 0.0
	for i in 120:
		var target := a.com_world() + Vector2(drag_speed / 60.0, 0.0)
		w.set_grab_target(target)
		w.step(1.0 / 60.0)
	var awake1 := 0
	for b in boxes:
		if b.awake:
			awake1 += 1
	print("拖动速度 %6.1f px/s | 抓前清醒 %d/3 -> 抓后 %d/3 | 被拖物体 x %.1f -> %.1f (移动 %+.1f)" % [
		drag_speed, awake0, awake1, x0, a.position.x, a.position.x - x0])

func _initialize() -> void:
	print("三个箱子并排（间距 0，互相紧贴），全部睡着后拖最左边那个")
	for s in [20.0, 60.0, 200.0, 600.0]:
		_run(s)
	quit(0)

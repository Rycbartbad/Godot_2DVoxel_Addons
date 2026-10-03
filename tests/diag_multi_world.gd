extends SceneTree
## 复现：同一个进程里连着建两个 PWorld，第二个的物体位置全是 (0,0)。
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _box(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _run(label: String, nbox: int, steps: int) -> void:
	var w := PWorld.new()
	var g := PBody.new()
	g.position = Vector2(0.0, 200.0)
	g.make_static()
	w.add_body(g, [_box(240, 16)])
	var boxes: Array = []
	for i in nbox:
		var b := PBody.new()
		b.position = Vector2(100.0, 200.0 - 16.0 * (i + 1))
		w.add_body(b, [_box(16, 16)])
		boxes.append(b)
	w.rp_debug = true
	print("%s：建好 %d 个箱子，rapier_id=%s" % [label, nbox, str(boxes.map(func(x): return x.rapier_id))])
	for i in mini(steps, 2):
		print("  --- 子步 %d ---" % i)
		w.step(1.0 / 60.0)
	w.rp_debug = false
	for i in steps - mini(steps, 2):
		w.step(1.0 / 60.0)
	for i in nbox:
		var b2: PBody = boxes[i]
		print("   box %d  位置 (%9.3f, %9.3f)  aabb=%s  awake=%s  rid=%d" % [
			i, b2.position.x, b2.position.y, str(b2.aabb), str(b2.awake), b2.rapier_id])

func _initialize() -> void:
	print("=== 同进程多世界 ===")
	_run("世界 A", 1, 200)
	_run("世界 B", 3, 400)
	_run("世界 C", 3, 400)
	quit(0)

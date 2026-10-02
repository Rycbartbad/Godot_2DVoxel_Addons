extends SceneTree
## 拖动为什么卡：抓取会让求解器退回 GDScript 对象路径
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const Grab := preload("res://src/physics/grab.gd")

func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

func _mk() -> Dictionary:
	var w := PWorld.new()
	var g := PBody.new()
	g.position = Vector2(-400.0, 0.0)
	g.make_static()
	w.add_body(g, [_block(800, 40)])
	var boxes: Array = []
	for r in 6:
		for c in 8:
			var b := PBody.new()
			b.position = Vector2(-160.0 + float(c) * 20.0, -18.0 - float(r) * 18.0)
			w.add_body(b, [_block(16, 16)])
			boxes.append(b)
	for i in 200:
		w.step(1.0 / 60.0)
	return {"w": w, "boxes": boxes}

func _initialize() -> void:
	var d := _mk()
	var w: PWorld = d["w"]
	var boxes: Array = d["boxes"]
	var dt := 1.0 / 60.0
	# 无抓取
	var best0 := 1.0e18
	for rep in 7:
		var t0 := Time.get_ticks_usec()
		w.step(dt)
		best0 = minf(best0, float(Time.get_ticks_usec() - t0))
	print("物体 %d | 无抓取 step = %7.3f ms" % [w.bodies.size(), best0 / 1000.0])
	# 加一个抓取（复刻拖动）
	var gr := Grab.new()
	gr.body = boxes[boxes.size() / 2]
	gr.local_anchor = Vector2.ZERO
	w.grabs.append(gr)
	var best1 := 1.0e18
	for rep in 7:
		gr.target = (gr.body as PBody).position + Vector2(0.0, -20.0)
		var t0 := Time.get_ticks_usec()
		w.step(dt)
		best1 = minf(best1, float(Time.get_ticks_usec() - t0))
	print("物体 %d | 拖动中 step = %7.3f ms | 慢 %.2fx" % [w.bodies.size(), best1 / 1000.0, best1 / best0])
	print("  （拖动时 _packed_manifolds=%s，求解走对象路径；流形 %d 个）" % [
		str(w._packed_manifolds), w.manifolds.size()])
	quit(0)

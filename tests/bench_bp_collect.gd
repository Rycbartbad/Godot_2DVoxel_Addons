extends SceneTree
## 宽相 collect 里到底花在哪：排序 / 编码 分别计时
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

func _scene() -> PWorld:
	var w := PWorld.new()
	w.sleeping_enabled = false
	w.ccd_enabled = false
	var g := PBody.new()
	g.position = Vector2(-1000.0, 0.0)
	g.make_static()
	w.add_body(g, [_block(2000, 40)])
	for i in 500:
		var f := PBody.new()
		f.position = Vector2(-600.0 + float(i % 50) * 24.0 + 6.0, -500.0 - float(i / 50) * 16.0)
		w.add_body(f, [_block(6, 6)])
		f.linear_velocity = Vector2(-60.0 + float(i % 11) * 12.0, 120.0)
	return w

func _best(f: Callable, reps: int) -> float:
	var b := 1.0e18
	for i in reps:
		var t0 := Time.get_ticks_usec()
		f.call()
		b = minf(b, float(Time.get_ticks_usec() - t0))
	return b / 1000.0

func _initialize() -> void:
	var w := _scene()
	for i in 150:
		w.step(1.0 / 60.0)
	var dt := 1.0 / 60.0
	var n := w.bodies.size()
	for b0: PBody in w.bodies:
		b0.compute_swept_aabb(dt)
	# 候选下标
	var idx: Array = []
	for i in n:
		var b: PBody = w.bodies[i]
		if b.rects.is_empty():
			continue
		if b.is_static and not b.awake:
			continue
		idx.append(i)
	print("物体 %d，候选 %d" % [n, idx.size()])

	# A. 现在的比较器：lambda 里做数组索引 + 属性访问
	var cur := _best(func() -> void:
		var a: Array = idx.duplicate()
		a.sort_custom(func(x: int, y: int) -> bool:
			return w.bodies[x].swept_aabb.position.x < w.bodies[y].swept_aabb.position.x), 9)
	print("A 比较器直读属性       %.3f ms" % cur)

	# B. 预抽 key 到 PackedFloat64Array
	var keys := PackedFloat64Array()
	keys.resize(n)
	var extract := _best(func() -> void:
		for i2 in n:
			keys[i2] = (w.bodies[i2] as PBody).swept_aabb.position.x, 9)
	print("B key 抽取（一次性）    %.3f ms" % extract)
	var pkt := _best(func() -> void:
		var a: Array = idx.duplicate()
		a.sort_custom(func(x: int, y: int) -> bool:
			return keys[x] < keys[y]), 9)
	print("C 比较器读 packed key   %.3f ms" % pkt)

	# D. 整个 collect 的其余部分：编码 body + rect
	var need_body := 32 + n * 104
	var bod := PackedByteArray(); bod.resize(need_body)
	var enc_body := _best(func() -> void:
		for i3 in n:
			var o := 32 + i3 * 104
			var b2: PBody = w.bodies[i3]
			bod.encode_double(o + 80, b2.aabb.position.x)
			bod.encode_double(o + 88, b2.aabb.position.y)
			bod.encode_double(o + 96, b2.aabb.size.x), 9)
	print("D 每体仅 3 个字段编码    %.3f ms  (全字段约 %.3f ms)" % [enc_body, enc_body * 3.0])
	quit(0)

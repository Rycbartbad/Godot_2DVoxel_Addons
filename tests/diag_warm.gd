extends SceneTree
## 把两个世界的 warm 缓存逐键打出来对比。
## 如果键或值不同，就说明 store_warm / 读取有问题。
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _shape(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

func _mk(batch: bool) -> PWorld:
	var w := PWorld.new()
	w.use_solver_batch = batch
	w.use_threads = false
	var g := PBody.new()
	g.position = Vector2(0.0, 200.0)
	g.make_static()
	w.add_body(g, [_shape(240, 16)])
	for i in 3:
		var b := PBody.new()
		b.position = Vector2(100.0, 200.0 - 16.0 * float(i + 1))
		w.add_body(b, [_shape(16, 16)])
	return w

func _dump_warm(label: String, w: PWorld) -> void:
	var keys: Array = []
	for k in w.solver._warm:
		keys.append(k)
	keys.sort()
	var s := ""
	for k in keys:
		var d: Dictionary = w.solver._warm[k]
		var fs: Array = []
		for f in d:
			fs.append(f)
		fs.sort()
		for f in fs:
			s += " [key=%d feat=%d ni=%.4f ti=%.4f]" % [k, f, d[f].x, d[f].y]
	print("  %-6s warm 条目 %d:%s" % [label, keys.size(), s])

func _initialize() -> void:
	var wa := _mk(false)
	var wb := _mk(true)
	for i in 6:
		wa.step(1.0 / 60.0)
		wb.step(1.0 / 60.0)
		print("--- step %d ---" % (i + 1))
		_dump_warm("对象", wa)
		_dump_warm("SoA", wb)
	quit(0)

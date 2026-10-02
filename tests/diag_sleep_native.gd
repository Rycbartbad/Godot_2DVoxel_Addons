extends SceneTree
## sleep_box 场景逐帧对比（含清醒数）
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

func _mk(native: bool) -> PWorld:
	var w := PWorld.new()
	w.sleeping_enabled = true
	w.use_native_broadphase = true
	w.use_native_solve = native
	var g := PBody.new()
	g.position = Vector2(-2000.0, 0.0)
	g.make_static()
	w.add_body(g, [_block(4000, 40)])
	for i2 in 12:
		var b := PBody.new()
		b.position = Vector2(-100.0 + float(i2 % 4) * 18.0, -9.0 - float(i2 / 4) * 18.0)
		w.add_body(b, [_block(16, 16)])
	return w

func _stat(w: PWorld) -> Array:
	var acc := 0.0
	var awake := 0
	for b in w.bodies:
		if b.is_static:
			continue
		if b.awake:
			awake += 1
		acc += b.position.x * 0.001 + b.position.y * 0.01 + b.rotation * 0.1
	return [acc, awake]

func _initialize() -> void:
	var wa := _mk(false)
	var wb := _mk(true)
	var first := -1
	for s in 600:
		wa.step(1.0 / 60.0)
		wb.step(1.0 / 60.0)
		var a := _stat(wa)
		var b := _stat(wb)
		var d: float = absf(float(a[0]) - float(b[0]))
		if (d > 0.0 or a[1] != b[1]) and first < 0:
			first = s
		if s % 40 == 0 or s <= first + 2 and first >= 0:
			print("步%3d | 对象 acc=%.9f awake=%2d | 扩展 acc=%.9f awake=%2d | 差 %.9f" % [
				s, a[0], a[1], b[0], b[1], d])
	print("首次分歧步 = %d" % first)
	quit(0)

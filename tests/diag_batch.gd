extends SceneTree
## 二分定位 SoA 求解器与对象路径的差异：同一个场景跑同一步数，逐帧对比。
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

func _scene(use_batch: bool) -> PWorld:
	var w := PWorld.new()
	w.sleeping_enabled = false
	w.use_threads = false
	w.use_solver_batch = use_batch
	var g := PBody.new()
	g.position = Vector2(-200.0, 0.0)
	g.make_static()
	w.add_body(g, [_block(400, 40)])
	var b := PBody.new()
	b.position = Vector2(0.0, -20.0)
	w.add_body(b, [_block(14, 14)])
	return w

func _snap(w: PWorld) -> Array:
	var out: Array = []
	for b in w.bodies:
		if b.is_static:
			continue
		out.append([b.position.x, b.position.y, b.rotation, b.linear_velocity.x,
			b.linear_velocity.y, b.angular_velocity])
	return out

func _initialize() -> void:
	var wa := _scene(false)
	var wb := _scene(true)
	print("步 | 对象路径 (x, y, vx, vy, w) | SoA 路径 | 最大差")
	var diverged := -1
	for s in 12:
		wa.step(1.0 / 60.0)
		wb.step(1.0 / 60.0)
		var a := _snap(wa)
		var b := _snap(wb)
		var d := 0.0
		for i in mini(a.size(), b.size()):
			for k in 6:
				d = maxf(d, absf(float(a[i][k]) - float(b[i][k])))
		print("%2d | 流形 %d/%d | (%.4f, %.4f, %.4f, %.4f) | (%.4f, %.4f, %.4f, %.4f) | %.9f" % [
			s, wa.manifolds.size(), wb.manifolds.size(),
			a[0][0], a[0][1], a[0][3], a[0][4], b[0][0], b[0][1], b[0][3], b[0][4], d])
		if d > 0.0 and diverged < 0:
			diverged = s
	print("首次分歧于第 %d 步" % diverged)
	quit(0)

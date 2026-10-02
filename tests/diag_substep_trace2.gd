extends SceneTree
## 从第一次接触开始，逐子步手工推进
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _block(w: int, h: int, mat: int = 1) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, mat)
	return s

func _initialize() -> void:
	var w := PWorld.new()
	w.gravity = Vector2.ZERO
	var wall := PBody.new()
	wall.position = Vector2(200, 0)
	wall.make_static()
	w.add_body(wall, [_block(8, 200)])
	var b := PBody.new()
	b.position = Vector2(170, 100)
	w.add_body(b, [_block(12, 12)])
	b.linear_velocity = Vector2(600, 0)
	print("从 x=170 起步，600 px/s；每帧手工跑子步，只打印 x>185 之后的")
	for f in 20:
		var n := w._compute_substeps(1.0 / 60.0)
		var sub := 1.0 / 60.0 / float(n)
		for i in n:
			w._integrate_forces(sub)
			w._broadphase(sub)
			var sep := 999.0
			var np := 0
			var cp := Vector2.ZERO
			for m in w.manifolds:
				sep = minf(sep, m.points[0].separation)
				np = m.points.size()
				cp = m.points[0].position
			w._wake_pass()
			w._solve(sub)
			var vx := b.linear_velocity.x
			w._integrate_transforms(sub)
			if b.position.x > 185.0 or b.com_world().x > 180.0:
				print("帧%2d 子步%d/%d x=%8.3f sep=%8.4f 点=%d 接触点=(%.2f,%.2f) | 解后vx=%9.2f w=%9.3f rot=%.5f" % [
					f, i, n, b.position.x, sep, np, cp.x, cp.y, vx, b.angular_velocity, b.rotation])
	quit(0)

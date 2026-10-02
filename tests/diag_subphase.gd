extends SceneTree
## 把子步拆成阶段，逐阶段打印 —— 看 sweep 看到的几何和窄相看到的是不是同一个
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
	var world := PWorld.new()
	world.gravity = Vector2.ZERO
	world.ccd_auto = false
	world.ccd_max_substeps = 4
	world.use_native_broadphase = false      # 用 GDScript 宽相，这样 manifolds 里有 sep
	var wall := PBody.new()
	wall.position = Vector2(200, 0)
	wall.make_static()
	world.add_body(wall, [_block(8, 200)])
	var b := PBody.new()
	b.position = Vector2(150, 100)
	b.ccd = true
	world.add_body(b, [_block(12, 12)])
	b.linear_velocity = Vector2(600, 0)
	print("start x=150；箱 OBB 左沿 = x（形状从 0 开始）")
	var frame := 0
	while b.position.x < 180.0 and frame < 30:
		world.step(1.0 / 60.0)
		frame += 1
	var n := world._compute_substeps(1.0 / 60.0)
	var sub := 1.0 / 60.0 / float(n)
	print("撞前 x=%.4f vx=%.2f；子步 %d 个，sub dt=%.6f，每子步自由位移 %.4f" % [
		b.position.x, b.linear_velocity.x, n, sub, 600.0 * sub])
	for i in n:
		world._integrate_forces(sub)
		world._broadphase(sub)
		var sep := 999.0
		for m in world.manifolds:
			sep = minf(sep, m.points[0].separation)
		var x0 := b.position.x
		world._wake_pass()
		world._solve(sub)
		var v_after := b.linear_velocity.x
		var disp := (b.linear_velocity + b.pseudo_linear_velocity) * sub
		world._integrate_transforms(sub)
		var mcount := 0
		var mpos := Vector2.ZERO
		for m in world.manifolds:
			mcount = m.points.size()
			mpos = m.points[0].position
		print("  子步%d x %8.3f->%8.3f | sep=%8.4f 点数=%d 接触点=(%.2f,%.2f) 质心=(%.2f,%.2f) | 解后 vx=%9.2f w=%9.4f rot=%.6f | 位移 %.4f 实际 %.4f" % [
			i, x0, b.position.x, sep, mcount, mpos.x, mpos.y,
			b.com_world().x, b.com_world().y,
			v_after, b.angular_velocity, b.rotation, disp.x, b.position.x - x0])
	quit(0)

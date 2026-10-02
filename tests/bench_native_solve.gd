extends SceneTree
## 宽相 + 求解的合计耗时：对象求解器 vs 扩展求解器
## （两边都用扩展宽相，隔离出求解器这一项的差别。注意 native 求解目前会与对象路径分叉，
##   所以这是"量级参考"，不是严格的同轨迹对比。）
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

func _scene(kind: String) -> PWorld:
	var w := PWorld.new()
	w.sleeping_enabled = false
	w.ccd_enabled = false
	w.use_threads = false
	w.use_native_broadphase = true
	var parts := kind.split(":")
	var fw := 2000.0
	if parts[0] == "frag":
		fw = 1400.0
	var g := PBody.new()
	g.position = Vector2(-fw * 0.5, 0.0)
	g.make_static()
	w.add_body(g, [_block(int(fw), 40)])
	match parts[0]:
		"pile":
			for r in int(parts[2]):
				for c in int(parts[1]):
					var b := PBody.new()
					b.position = Vector2(-float(int(parts[1])) * 7.0 + float(c) * 14.0, -7.0 - float(r) * 14.0)
					w.add_body(b, [_block(14, 14)])
		"frag":
			for side in 2:
				var wall := PBody.new()
				wall.position = Vector2((-1.0 if side == 0 else 1.0) * fw * 0.5, -600.0)
				wall.make_static()
				w.add_body(wall, [_block(20, 600)])
			for i in int(parts[1]):
				var f := PBody.new()
				f.position = Vector2(-600.0 + float(i % 50) * 24.0 + 6.0, -500.0 - float(i / 50) * 16.0)
				w.add_body(f, [_block(6, 6)])
				f.linear_velocity = Vector2(-60.0 + float(i % 11) * 12.0, 120.0)
	return w

func _row(kind: String, steps: int) -> void:
	var wa := _scene(kind)
	var wb := _scene(kind)
	wa.use_native_solve = false
	wb.use_native_solve = true
	for i in steps:
		wa.step(1.0 / 60.0)
		wb.step(1.0 / 60.0)
	var dt := 1.0 / 60.0
	var best_a := 1.0e18
	var best_b := 1.0e18
	for rep in 7:
		var t0 := Time.get_ticks_usec()
		wa._broadphase(dt); wa._solve(dt)
		var t1 := Time.get_ticks_usec()
		best_a = minf(best_a, float(t1 - t0))
		var t2 := Time.get_ticks_usec()
		wb._broadphase(dt); wb._solve(dt)
		var t3 := Time.get_ticks_usec()
		best_b = minf(best_b, float(t3 - t2))
	print("%-12s 流形 %4d 点 %4d | 对象求解 %7.3f ms | 扩展求解 %7.3f ms | %5.2fx" % [
		kind, wa._bp_count, wa._bp_points,
		best_a / 1000.0, best_b / 1000.0, best_a / maxf(0.001, best_b)])

func _initialize() -> void:
	print("=== 宽相 + 求解（两边都用扩展宽相）===")
	_row("pile:10:8", 60)
	_row("pile:20:12", 120)
	_row("frag:240", 120)
	_row("frag:500", 150)
	quit(0)

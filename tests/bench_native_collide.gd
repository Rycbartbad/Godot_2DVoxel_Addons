extends SceneTree
## 宽相三种配置对比（三条路径产出的流形逐位一致，所以可以在同一个世界里来回切）
##   0 = 全 GDScript
##   1 = 只把 collide 搬到扩展
##   2 = 整个宽相搬到扩展
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

func _snap(w: PWorld) -> String:
	var s := ""
	for m in w.manifolds:
		s += "%.17f,%.17f|" % [m.normal.x, m.normal.y]
		for p in m.points:
			s += "%.17f,%.17f,%.17f,%d;" % [p.position.x, p.position.y, p.depth, p.feature_id]
	return s

func _cfg(w: PWorld, mode: int) -> void:
	w.use_native_broadphase = (mode == 2)
	w.use_native_collide = (mode >= 1)
	# 本 bench 只比宽相，求解器固定走对象路径。
	# ⚠️ 否则 native 求解器会让 _broadphase 不再建流形对象，_snap 取到空串，
	#    "逐位一致"这栏就成了"两边都是空"的假绿。
	w.use_native_solve = false

func _row(kind: String, steps: int) -> void:
	var w := _scene(kind)
	for i in steps:
		w.step(1.0 / 60.0)
	var dt := 1.0 / 60.0
	# 一致性检查
	_cfg(w, 0); w._broadphase(dt); var s0 := _snap(w)
	_cfg(w, 1); w._broadphase(dt); var s1 := _snap(w)
	_cfg(w, 2); w._broadphase(dt); var s2 := _snap(w)
	var best := [1.0e18, 1.0e18, 1.0e18]
	for rep in 9:
		for mode in 3:
			_cfg(w, mode)
			var t0 := Time.get_ticks_usec()
			w._broadphase(dt)
			var t1 := Time.get_ticks_usec()
			best[mode] = minf(best[mode], float(t1 - t0))
	print("%-12s 流形 %4d 点 %4d | 全 GDScript %7.3f | 仅 collide %7.3f | **整宽相 %7.3f ms** | 相对 GDScript %5.2fx | 逐位一致 %s/%s" % [
		kind, w.manifolds.size(), w.last_contacts, best[0] / 1000.0, best[1] / 1000.0, best[2] / 1000.0,
		best[0] / maxf(0.001, best[2]), str(s1 == s0), str(s2 == s0)])

func _initialize() -> void:
	print("=== 宽相：全 GDScript / 仅 collide / 整个宽相 ===")
	_row("pile:10:8", 60)
	_row("pile:20:12", 120)
	_row("frag:240", 120)
	_row("frag:500", 150)
	quit(0)

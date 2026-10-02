extends SceneTree
## 一个 step 的时间花在哪：逐阶段单独计时（各 9 次取最小值）
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
	var parts := kind.split(":")
	var g := PBody.new()
	g.position = Vector2(-1000.0, 0.0)
	g.make_static()
	w.add_body(g, [_block(2000, 40)])
	match parts[0]:
		"pile":
			for r in int(parts[2]):
				for c in int(parts[1]):
					var b := PBody.new()
					b.position = Vector2(-float(int(parts[1])) * 7.0 + float(c) * 14.0, -7.0 - float(r) * 14.0)
					w.add_body(b, [_block(14, 14)])
		"frag":
			var wall := PBody.new()
			wall.position = Vector2(-700.0, -600.0)
			wall.make_static()
			w.add_body(wall, [_block(20, 600)])
			var wall2 := PBody.new()
			wall2.position = Vector2(680.0, -600.0)
			wall2.make_static()
			w.add_body(wall2, [_block(20, 600)])
			for i in int(parts[1]):
				var f := PBody.new()
				f.position = Vector2(-600.0 + float(i % 50) * 24.0 + 6.0, -500.0 - float(i / 50) * 16.0)
				w.add_body(f, [_block(6, 6)])
				f.linear_velocity = Vector2(-60.0 + float(i % 11) * 12.0, 120.0)
	return w

func _us(f: Callable, reps: int) -> float:
	var best := 1.0e18
	for i in reps:
		var t0 := Time.get_ticks_usec()
		f.call()
		best = minf(best, float(Time.get_ticks_usec() - t0))
	return best

func _row(kind: String, settle: int) -> void:
	var w := _scene(kind)
	for i in settle:
		w.step(1.0 / 60.0)
	var dt := 1.0 / 60.0
	var t_clr := _us(func() -> void:
		for b0 in w.bodies: b0.clear_pseudo(), 9)
	var t_force := _us(func() -> void: w._integrate_forces(dt), 9)
	var t_bp := _us(func() -> void: w._broadphase(dt), 9)
	var t_wake := _us(func() -> void: w._wake_pass(), 9)
	var t_solve := _us(func() -> void: w._solve(dt), 9)
	var t_itr := _us(func() -> void: w._integrate_transforms(dt), 9)
	var t_aabb := _us(func() -> void:
		for b in w.bodies:
			if not b.is_static: b.update_aabb(), 9)
	var t_sleep := _us(func() -> void: w._update_sleep(dt), 9)
	var tot := t_clr + t_force + t_bp + t_wake + t_solve + t_itr + t_aabb + t_sleep
	print("=== %s  物体 %d 流形 %d ===" % [kind, w.bodies.size(), w._bp_count])
	var rows := [
		["clear_pseudo", t_clr], ["integrate_forces", t_force], ["broadphase", t_bp],
		["wake_pass", t_wake], ["solve", t_solve], ["integrate_transforms", t_itr],
		["update_aabb", t_aabb], ["update_sleep", t_sleep]]
	for r in rows:
		print("   %-20s %8.3f ms  %5.1f%%" % [r[0], float(r[1]) / 1000.0, 100.0 * float(r[1]) / tot])
	print("   %-20s %8.3f ms" % ["合计", tot / 1000.0])
	print("   宽相内部分解: collect %.3f / resolve %.3f ms" % [w.bp_collect_us / 1000.0, w.bp_resolve_us / 1000.0])

func _initialize() -> void:
	_row("pile:20:12", 150)
	_row("frag:500", 150)
	quit(0)

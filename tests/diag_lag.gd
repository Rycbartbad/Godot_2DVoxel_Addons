extends SceneTree
## 定位"很卡"：把撞击规则拆成三块分别计时。
##   (a) 接触事件本身的每步开销（demo 里 _apply_impact_damage 会无条件打开它）
##   (b) 一次 detach 的代价
##   (c) 对照一次 fracture 的代价
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const Destruction := preload("res://src/core/destruction.gd")

func _slab(w, n: int) -> void:
	for i in n:
		var b := PBody.new()
		b.position = Vector2(i * 44 - 200, -200 - i * 30)
		var s := PixelShape.new()
		s.fill_rect(Rect2i(0, 0, 40, 40), 1)
		w.add_body(b, [s], Callable(), true)

func _scene(events: bool) -> PWorld:
	var w := PWorld.new()
	w.gravity = Vector2(0, 600)
	w.contact_events_enabled = events
	var g := PBody.new()
	g.position = Vector2(0, 200)
	g.make_static()
	var gs := PixelShape.new()
	gs.fill_rect(Rect2i(0, 0, 600, 40), 1)
	w.add_body(g, [gs], Callable(), true)
	_slab(w, 12)
	return w

func _time_steps(w, n: int) -> float:
	var t0 := Time.get_ticks_usec()
	for i in n:
		w.step(1.0 / 60.0)
	return (Time.get_ticks_usec() - t0) / 1000.0

func _initialize() -> void:
	# (a) 事件开关的每步开销（先落稳，再计时 200 步）
	var wa := _scene(false)
	_time_steps(wa, 120)
	var ta := _time_steps(wa, 200)
	var wb := _scene(true)
	_time_steps(wb, 120)
	var tb := _time_steps(wb, 200)
	print("(a) 200 步：事件关 %.1f ms / 事件开 %.1f ms -> 每帧差 %.3f ms（接触 %d 对）" % [
		ta, tb, (tb - ta) / 200.0, wb.contact_pair_count()])

	# (b) 一次 detach 的代价
	var w1 := PWorld.new()
	var b1 := PBody.new()
	var s1 := PixelShape.new()
	s1.fill_rect(Rect2i(0, 0, 200, 200), 1)      # 大一点，逼近 demo 里的墙
	w1.add_body(b1, [s1], Callable(), true)
	var t1 := Time.get_ticks_usec()
	w1.detach(b1, Destruction.Damage.circle(Vector2(100, 100), 6.0))
	var dt1 := (Time.get_ticks_usec() - t1) / 1000.0

	# (c) 对照 fracture（同样大小的形状、同样大小的洞）
	var w2 := PWorld.new()
	var b2 := PBody.new()
	var s2 := PixelShape.new()
	s2.fill_rect(Rect2i(0, 0, 200, 200), 1)
	w2.add_body(b2, [s2], Callable(), true)
	var t2 := Time.get_ticks_usec()
	w2.fracture(b2, Destruction.Damage.circle(Vector2(100, 100), 6.0))
	var dt2 := (Time.get_ticks_usec() - t2) / 1000.0

	print("(b) detach 一次 = %.3f ms（200x200 内部挖洞）" % dt1)
	print("(c) fracture 一次 = %.3f ms（同样条件）" % dt2)
	print("=> detach 比 fracture 慢 %.1f 倍" % (dt1 / maxf(dt2, 0.001)))
	quit(0)

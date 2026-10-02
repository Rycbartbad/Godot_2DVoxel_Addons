extends SceneTree
## 「如果有编译器，能省下什么？」—— 直接量 **Variant 装箱 / Dictionary 分配** 的税。
##
## GDScript 的所有容器访问都返回 Variant：Dictionary 取值要装箱，
## 再赋值给有类型的变量又要拆箱。这正是 JIT/AOT 能消掉、而解释器消不掉的部分。
## 所以这里拿 sat_signed() 开刀：同一个几何算法，
##   旧：返回 Dictionary（每次调用分配一个 HashMap）
##   新：写进 static 类型化字段（零分配、零装箱）
## 几何计算一字不改，差值就是纯粹的"装箱 + 分配"税。
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const Collide := preload("res://src/physics/collide.gd")

func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

# --- 新写法的临时存放点（类型化，静态）---
static var _sep := 0.0
static var _nx := 0.0
static var _ny := 0.0
static var _from_a := true

## 与 Collide.sat_signed 完全相同的算式，只是**不构造 Dictionary**
static func _sat_scratch(a: Collide.OBB, bb: Collide.OBB) -> void:
	var axes := [a.u, a.v, bb.u, bb.v]
	var best_sep := -INF
	var best_axis_x := 1.0
	var best_axis_y := 0.0
	var best_from_a := true
	var d_center := bb.center - a.center
	for i in 4:
		var axis: Vector2 = axes[i]
		var ra := a.project_radius(axis)
		var rb := bb.project_radius(axis)
		var d := d_center.dot(axis)
		var sep := absf(d) - (ra + rb)
		if sep > best_sep:
			best_sep = sep
			if d >= 0.0:
				best_axis_x = axis.x
				best_axis_y = axis.y
			else:
				best_axis_x = -axis.x
				best_axis_y = -axis.y
			best_from_a = i < 2
	_sep = best_sep
	_nx = best_axis_x
	_ny = best_axis_y
	_from_a = best_from_a

var _pairs: Array = []

func _gather() -> void:
	var world := PWorld.new()
	world.sleeping_enabled = false
	world.use_threads = false
	var g := PBody.new()
	g.position = Vector2(-200.0, 0.0)
	g.make_static()
	world.add_body(g, [_block(600, 40)])
	for c in 8:
		for r in 6:
			var b2 := PBody.new()
			b2.position = Vector2(-150.0 + float(c) * 14.0 + 7.0, -7.0 - float(r) * 14.0)
			world.add_body(b2, [_block(14, 14)])
	for i in 40:
		world.step(1.0 / 60.0)
	for A: PBody in world.bodies:
		if A.rects.is_empty():
			continue
		for B: PBody in world.bodies:
			if B.rects.is_empty():
				continue
			_pairs.append([Collide.obb_from_local_rect(A, A.rects[0]),
				Collide.obb_from_local_rect(B, B.rects[0])])

func _time_dict(reps: int) -> float:
	var best := 1.0e18
	for rep in reps:
		var acc := 0.0
		var t0 := Time.get_ticks_usec()
		for pr: Array in _pairs:
			var s := Collide.sat_signed(pr[0], pr[1])
			acc += float(s["sep"])
		var dt := float(Time.get_ticks_usec() - t0)
		_sink += acc
		best = minf(best, dt)
	return best

func _time_scratch(reps: int) -> float:
	var best := 1.0e18
	for rep in reps:
		var acc := 0.0
		var t0 := Time.get_ticks_usec()
		for pr: Array in _pairs:
			_sat_scratch(pr[0], pr[1])
			acc += _sep
		var dt := float(Time.get_ticks_usec() - t0)
		_sink += acc
		best = minf(best, dt)
	return best

var _sink := 0.0

func _initialize() -> void:
	_gather()
	var n := _pairs.size()
	print("=== sat_signed：Dictionary 装箱 vs 静态类型字段（%d 对 OBB）===" % n)
	var d := _time_dict(7)
	var s := _time_scratch(7)
	print("  返回 Dictionary : %8.1f us/轮  (%.3f us/次)" % [d, d / float(n)])
	print("  写静态类型字段 : %8.1f us/轮  (%.3f us/次)" % [s, s / float(n)])
	print("  => 装箱 + 分配 的税: %.2fx（即 %.0f%% 的开销）" % [d / maxf(0.01, s), (1.0 - s / maxf(0.01, d)) * 100.0])
	# 顺带：一次"空结果 Dictionary"分配本身要多久（旧代码每对一次）
	var t0 := Time.get_ticks_usec()
	var sink2 := 0
	for i in 20000:
		var e := {"normal": Vector2.RIGHT, "points": []}
		sink2 += e.size()
	var t1 := (Time.get_ticks_usec() - t0) / 1000.0
	print("  单次空结果 Dictionary+Array 分配: %.3f us  (%d 次共 %.1f ms)" % [t1 * 1000.0 / 20000.0, 20000, t1])
	quit(0)

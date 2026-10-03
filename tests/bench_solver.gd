extends SceneTree
## 求解器内层优化用的基准。
##
## 为什么不能只报 ms：本机噪声很大（同场景两次能差 60%）。
## 所以每次运行都同时报三个口径，跨版本比较只看后两个：
##   1) solve_ms          —— 绝对值，仅供感受
##   2) solve / broad     —— **用未被优化的 broadphase 当参照物**，抵消机器漂移
##   3) ns / 流形求解     —— 单元成本，跨场景可比
## 全部取 reps 次的最小值（最小值最接近"没被打扰的那一次"）。
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

func _build(kind: String) -> PWorld:
	var world := PWorld.new()
	world.sleeping_enabled = false
	world.ccd_enabled = false
	var g := PBody.new()
	g.position = Vector2(-2000.0, 0.0)
	g.make_static()
	world.add_body(g, [_block(4000, 40)])
	var parts := kind.split(":")
	match parts[0]:
		"stack":
			# 多层堆叠：2 点流形为主，正是块求解器的战场
			var cols := int(parts[1])
			var rows := int(parts[2])
			for c in cols:
				for r in rows:
					var b := PBody.new()
					b.position = Vector2(-200.0 + float(c) * 60.0, -7.0 - float(r) * 14.0)
					world.add_body(b, [_block(14, 14)])
		"pile":
			# 紧贴箱阵：接触最多、最挤
			for r2 in int(parts[2]):
				for c2 in int(parts[1]):
					var b2 := PBody.new()
					b2.position = Vector2(-200.0 + float(c2) * 14.0 + 7.0, -7.0 - float(r2) * 14.0)
					world.add_body(b2, [_block(14, 14)])
		"frags":
			for i in int(parts[1]):
				var f := PBody.new()
				f.position = Vector2(-1200.0 + float(i % 60) * 12.0, -400.0 - float(i / 60) * 14.0)
				world.add_body(f, [_block(4, 4)])
				f.linear_velocity = Vector2(-120.0 + float(i % 13) * 20.0, 100.0)
	return world

## 一次测量：重建 -> 预热 -> 分阶段计时
func _once(kind: String, steps: int) -> Array:
	var world := _build(kind)
	for i in 60:
		world.step(1.0 / 60.0)
	var solve_us := 0
	var broad_us := 0
	var substeps := 0
	for s in steps:
		var dt := 1.0 / 60.0
		var n: int = world._compute_substeps(dt)
		substeps += n
		for i in n:
			var sub: float = dt / float(n)
			var t0 := Time.get_ticks_usec()
			for b0 in world.bodies:
				b0.clear_pseudo()
			world._integrate_forces(sub)
			var t1 := Time.get_ticks_usec()
			world._broadphase(sub)
			var t2 := Time.get_ticks_usec()
			world._wake_pass()
			world._solve(sub)
			var t3 := Time.get_ticks_usec()
			world.solver.store_warm(world.manifolds)
			world._integrate_transforms(sub)
			for b in world.bodies:
				if not b.is_static:
					b.update_aabb()
			world._update_sleep(sub)
			broad_us += t2 - t1
			solve_us += t3 - t2
	# 单位成本：每次"流形求解"（一条流形一次迭代）多少纳秒
	var manifolds := world.manifolds.size()
	var points := 0
	for m in world.manifolds:
		points += m.points.size()
	var unit := float(solve_us) * 1000.0 / maxf(1.0, float(manifolds * world.solver.iterations * substeps))
	return [float(solve_us) / 1000.0 / float(steps), float(broad_us) / 1000.0 / float(steps),
		unit, manifolds, points, float(substeps) / float(steps)]

func _report(kind: String, steps: int, reps: int) -> void:
	var best: Array = []
	for r in reps:
		var res := _once(kind, steps)
		if best.is_empty() or res[0] < best[0]:
			best = res
	print("%-14s 流形 %4d 接触点 %4d | solve %7.3f ms (min) | broad %7.3f ms | solve/broad %5.2f | %6.1f ns/流形求解" % [
		kind, best[3], best[4], best[0], best[1], best[0] / maxf(0.001, best[1]), best[2]])

func _initialize() -> void:
	print("=== 求解器内层成本基准（单核，reps 取最小值）===")
	var reps := 5
	_report("stack:6:5", 25, reps)
	_report("pile:8:6", 25, reps)
	_report("pile:10:8", 25, reps)
	_report("frags:240", 25, reps)
	quit(0)

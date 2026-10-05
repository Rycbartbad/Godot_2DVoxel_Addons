extends SceneTree
## 破坏管线的**分段耗时**诊断（表 ⑥ 的可行性依据；不是闸门）。
##
## 量什么：
##   · 端到端 fracture / detach（一刀把形状切成两半）；
##   · split 的三段：_components_cpu（每块泛洪 + 节点表）/ _group（接缝 union-find + 归组）
##     / _assemble（逐块 blit + 组装）；
##   · MassProps.compute（质量属性）与 GreedyRects.decompose（矩形分解）。
##
## 实测（2026-10，本机）：
##   768x100 静态底板（76400 像素 / 1248 块）：
##     _components_cpu 1.79 | _group 接缝 4.74 + 归组 1.00 | _assemble blit 7.27
##     MassProps 6.43 | decompose 0.48 | 端到端 fracture 31.3 / detach 12.0
##   200x200 动态体（39200 像素 / 625 块）：
##     _components_cpu 0.56 | _group ~2.7 | _assemble ~3 | MassProps 2.84
##     端到端 fracture 19.3 / detach 17.1
##
## 结论（写进 development_log）：瓶颈**不是"算法在 GDScript 里"**，而是
##   · _assemble 的 7.27 ms = **2496 次原生调用**（每个分片每块一次 blit_mask_from，
##     每次只搬 64 字节 + 一个掩码）—— 要的是**批量 op**；
##   · 接缝 union 循环是纯解释器开销（试过把 has()+[] 换成 get()，**反而慢 9%**）。
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const Destruction := preload("res://src/core/destruction.gd")
const MassProps := preload("res://src/core/mass_props.gd")
const GreedyRects := preload("res://src/core/greedy_rects.gd")

func _shape(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _cut(w: int, h: int) -> PixelShape:
	var s := _shape(w, h)
	Destruction.apply_damage(s, Destruction.Damage.segment(Vector2(w / 2, -5), Vector2(w / 2, h + 5), 2.0))
	return s

func _best(f: Callable, reps: int) -> float:
	var best := 1.0e9
	for i in reps:
		var t0 := Time.get_ticks_usec()
		var sink = f.call()
		best = minf(best, float(Time.get_ticks_usec() - t0) / 1000.0)
		if sink is int and sink == -12345:
			print("never")
	return best

func _stages(w: int, h: int) -> void:
	var s := _cut(w, h)
	var keys: Array = s.chunks.keys()
	var parts: Dictionary = Destruction._components_cpu(s, keys)
	var groups: Dictionary = Destruction._group(s, keys, parts)
	print("=== %dx%d（%d 块，%d 像素，%d 个分量）===" % [w, h, keys.size(), s.pixel_count(), groups.size()])
	print("  _components_cpu（每块泛洪 + 节点表）  = %7.3f ms" % _best(func(): return Destruction._components_cpu(s, keys).size(), 5))
	print("  _group（接缝 union-find + 归组）      = %7.3f ms" % _best(func(): return Destruction._group(s, keys, parts).size(), 5))
	print("  _assemble（逐块 blit + 组装）        = %7.3f ms" % _best(func(): return Destruction._assemble(s, keys, parts, 4).size(), 5))
	print("  split（= 上面三段）                  = %7.3f ms" % _best(func(): return Destruction.split(s, 4).size(), 5))
	print("  MassProps.compute（质量属性）        = %7.3f ms" % _best(func(): return MassProps.compute(s, Callable(), Callable(), Callable()).pixel_count, 5))
	print("  GreedyRects.decompose（矩形分解）    = %7.3f ms" % _best(func(): return GreedyRects.decompose(s, 64).rects.size(), 5))

func _end_to_end(w: int, h: int, stat: bool) -> void:
	var best_f := 1.0e9
	var best_d := 1.0e9
	for rep in 5:
		var world := PWorld.new()
		world.gravity = Vector2.ZERO
		var b := PBody.new()
		if stat:
			b.make_static()
		world.add_body(b, [_shape(w, h)])
		for i in 20:
			world.step(1.0 / 60.0)
		var t0 := Time.get_ticks_usec()
		world.fracture(b, Destruction.Damage.segment(Vector2(w / 2, -5), Vector2(w / 2, h + 5), 2.0))
		best_f = minf(best_f, float(Time.get_ticks_usec() - t0) / 1000.0)
		var world2 := PWorld.new()
		world2.gravity = Vector2.ZERO
		var b2 := PBody.new()
		if stat:
			b2.make_static()
		world2.add_body(b2, [_shape(w, h)])
		for i in 20:
			world2.step(1.0 / 60.0)
		t0 = Time.get_ticks_usec()
		world2.detach(b2, Destruction.Damage.segment(Vector2(w / 2, -5), Vector2(w / 2, h + 5), 2.0))
		best_d = minf(best_d, float(Time.get_ticks_usec() - t0) / 1000.0)
	print("=== %dx%d 端到端（一刀切两半）fracture = %.3f ms | detach = %.3f ms ===" % [w, h, best_f, best_d])

func _initialize() -> void:
	_stages(768, 100)
	_stages(200, 200)
	_end_to_end(768, 100, true)
	_end_to_end(200, 200, false)
	quit(0)

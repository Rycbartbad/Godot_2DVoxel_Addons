extends SceneTree
## 流体性能基准：原生 PixelFluid vs GDScript 参照实现。
##
## 两个规模：
##   · 参照规模 130 粒子 / 17x18 格 —— 与 SandSim.c 同参数，用来对得上历史数字；
##   · 瓶子规模 ~300 粒子 / 26x14 格 —— ink-2 那个血瓶的实际量级。
##
## ⚠️ 两边**必须跑同一份数据**（同样的初始排布、同样的步数），否则比的是两件事。
##    做法是各造一个场、各自 init_particles 到同一个数量。
const FluidPBF := preload("res://src/fluid/fluid_pbf.gd")

func _mk(nx: int, ny: int, count: int, force_gd: bool) -> Object:
	var f = FluidPBF.new()
	f.resize_grid(nx, ny)
	f.max_particles = count
	f.init_particles(count)
	f.fill_ratio = -1.0
	if force_gd:
		f._native_checked = true
		f._native = null
	return f

func _run(nx: int, ny: int, count: int, steps: int, force_gd: bool) -> Array:
	var f = _mk(nx, ny, count, force_gd)
	# 预热：让 rest_density 定出来，避免首帧的一次性开销算进去
	for i in 20:
		f.step(0.0, 9.8)
	var t0 := Time.get_ticks_usec()
	for i in steps:
		f.step(0.0, 9.8)
	var t1 := Time.get_ticks_usec()
	return [float(t1 - t0) / 1000.0 / float(steps), f.particle_count()]

func _initialize() -> void:
	var native_ok := ClassDB.class_exists("PixelFluid")
	print("PixelFluid 扩展: ", "可用" if native_ok else "**未加载**（原生那一列会是参照实现）")

	var cases := [
		{"name": "参照规模", "nx": 17, "ny": 18, "n": 130, "steps": 300},
		{"name": "瓶子规模", "nx": 26, "ny": 14, "n": 300, "steps": 200},
	]
	print("")
	print("%-10s %6s %6s %10s %14s %10s" % ["规模", "网格", "粒子", "参照 ms/步", "原生 ms/步", "倍数"])
	for c in cases:
		var gd := _run(c["nx"], c["ny"], c["n"], c["steps"], true)
		var nt := _run(c["nx"], c["ny"], c["n"], c["steps"], not native_ok)
		var speedup: float = gd[0] / nt[0] if nt[0] > 0.0 else 0.0
		print("%-10s %6s %6d %10.3f %14.4f %9.1fx" % [
			c["name"], "%dx%d" % [c["nx"], c["ny"]], nt[1], gd[0], nt[0], speedup])
	print("")
	print("（60 FPS 的预算是 16.7 ms/帧。瓶子规模那一行才是 ink-2 关心的。）")
	quit(0)

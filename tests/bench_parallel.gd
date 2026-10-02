extends SceneTree
## 并行方案 A/B 基准 —— **重复 + 交叉**测量。
##
## 为什么必须这样测：单次测量在本机上噪声极大（同场景两次跑出 63 ms 和 104 ms）。
## 于是做法是：
##   1. 同一配置重复 reps 次，取**最小值**（最小值最接近"没有被打扰的那次"）；
##   2. 不同配置**交叉**进行（round-robin），抵消机器随时间漂移；
##   3. 每次都重建场景，避免残留状态影响。
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

const MODES := ["串行", "岛并行", "着色"]

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
	# 地面横跨 x∈[-2000,2000]，顶面 y=0（不会有物体掉出世界边缘）
	var g := PBody.new()
	g.position = Vector2(-2000.0, 0.0)
	g.make_static()
	world.add_body(g, [_block(4000, 40)])
	var kind_parts := kind.split(":")
	match kind_parts[0]:
		"towers":
			# N 座互不相连的小塔（塔距 40，塔内 3 箱面贴面）
			var piles := int(kind_parts[1])
			for p in piles:
				var gx := -1800.0 + float(p) * 40.0
				for i in 3:
					var b := PBody.new()
					b.position = Vector2(gx, -7.0 - float(i) * 14.0)
					world.add_body(b, [_block(14, 14)])
		"pile":
			# 一个紧贴箱阵（cols x rows，面贴面）=> 一个很重的岛
			var cols := int(kind_parts[1])
			var rows := int(kind_parts[2])
			for r in rows:
				for c in cols:
					var b2 := PBody.new()
					b2.position = Vector2(-200.0 + float(c) * 14.0 + 7.0, -7.0 - float(r) * 14.0)
					world.add_body(b2, [_block(14, 14)])
		"frags":
			# N 个 4x4 碎块，带初速飞散 —— 最接近"炸完之后"的真实场景
			var nf := int(kind_parts[1])
			for i in nf:
				var f := PBody.new()
				f.position = Vector2(-1200.0 + float(i % 60) * 12.0, -400.0 - float(i / 60) * 14.0)
				world.add_body(f, [_block(4, 4)])
				f.linear_velocity = Vector2(-120.0 + float(i % 13) * 20.0, 100.0)
	return world

func _apply_mode(world: PWorld, mode: String) -> void:
	match mode:
		"串行":
			world.use_threads = false
			world.use_coloring = false
		"岛并行":
			world.use_threads = true
			world.use_coloring = false
		"着色":
			world.use_threads = true
			world.use_coloring = true

## 一次测量：建场景 -> 预热 -> 计时
func _once(kind: String, mode: String, steps: int) -> float:
	var world := _build(kind)
	_apply_mode(world, mode)
	for i in 60:
		world.step(1.0 / 60.0)
	var t0 := Time.get_ticks_usec()
	for i in steps:
		world.step(1.0 / 60.0)
	return (Time.get_ticks_usec() - t0) / 1000.0 / float(steps)

func _stats(kind: String, steps: int, reps: int) -> void:
	var results := {}
	var islands := 0
	var biggest := 0
	var total := 0
	for mode in MODES:
		results[mode] = []
	# 交叉重复：每一轮把三种模式各跑一次
	for r in reps:
		for mode in MODES:
			(results[mode] as Array).append(_once(kind, mode, steps))
	# 场景结构：必须先 step 一次，流形才会生成（没 step 过的世界没有接触）
	var w := _build(kind)
	_apply_mode(w, "串行")
	for i in 30:
		w.step(1.0 / 60.0)
	var isl := w._build_islands()
	for isle: Dictionary in isl:
		var cnt: int = (isle["manifolds"] as Array).size()
		biggest = maxi(biggest, cnt)
		total += cnt
	islands = isl.size()
	# 打印：min / median
	var line := "%-22s 岛%3d 最大岛%3d(%2.0f%%) 流形%4d |" % [
		kind, islands, biggest, 100.0 * float(biggest) / maxf(1.0, float(total)), total]
	for mode in MODES:
		var arr: Array = results[mode]
		arr.sort()
		var mn: float = arr[0]
		var med: float = arr[arr.size() / 2]
		line += " %s min%7.2f med%7.2f |" % [mode, mn, med]
	var base: float = (results["串行"] as Array)[0]
	for mode in ["岛并行", "着色"]:
		var arr2: Array = results[mode]
		arr2.sort()
		line += " %s %.2fx" % [mode, base / maxf(0.001, arr2[0])]
	print(line)

func _initialize() -> void:
	print("=== 并行方案 A/B（16 核，关休眠/CCD，交叉重复取最小值）===")
	var reps := 5
	var steps := 30
	_stats("towers:16", steps, reps)
	_stats("towers:36", steps, reps)
	_stats("pile:8:6", steps, reps)
	_stats("pile:6:4", steps, reps)
	_stats("frags:240", steps, reps)
	quit(0)

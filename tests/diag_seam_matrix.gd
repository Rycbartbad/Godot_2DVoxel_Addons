extends SceneTree
## **矩形布局试验台** —— 把"接缝"这一个变量单独拎出来，验任何布局假设。
##
## 做法：地面先用实心 4096x40 建好（decompose 给 1 个矩形），然后**直接注入**想测的
## 矩形布局（body.rects + rects_rev -> op5 推给 Rapier）。箱子位置、物理参数、步数
## 全部不变 —— 唯一的变量就是地面被切成了什么形状。
##
## 2026-10 实测（箱子在局部 1793~2107，300 步）：
##
## | 地面布局 | 矩形 | 结果 |
## |---|---|---|
## | [0,4000] 整块 | 1 | 完全静止 |
## | 按块那 6 个（接缝 2048/3072/...） | 6 | **倒塌**（2 个翻 90°、滑 47 像素）|
## | 同上、顺序倒过来 | 6 | 倒塌（dx 45.4）-> **与顺序无关** |
## | 6 个但互相**重叠 1 像素** | 6 | 倒塌（dx 44.8）-> **裂缝/重叠不是原因** |
## | 2 个（[0,3968]+[3968,4000]） | 2 | 完全静止 |
## | 6 个但接缝全在箱子左边（x<1760） | 6 | 完全静止 |
## | 6 个但接缝处留 1 像素**真空隙** | 6 | 倒塌（dx 32.2）|
## | 3 个（接缝 2048 与 2049 都贴着箱子） | 3 | 倒塌 |
##
## 结论：**触发条件是"矩形边界落在离静止物体边缘 ~1 像素处"** ——
## 不是矩形数（6 个也能稳）、不是顺序、不是裂缝、不是碰撞体数量。
## 所以"把实心区域并成最大行程（接缝少且落在区域末端）"能解决**人造接缝**这一类；
## 但任何**残留**边界对停在它 1 像素内的物体仍然是雷 —— 要走那条路必须自带
## 一个"停在边界 1 像素处"的基准守住它。
##
## ⚠️ 这个探针只**打印**不断言：好布局必须稳，坏布局会塌（那是已知缺陷，
##    不该被断言锁死）。要断言请针对具体布局写新测试。
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

## 把 [0,4000) 按给定的右沿切成一排 40 高的矩形（overlap 用来造"重叠"那一组）
func _split(edges: Array, overlap: int = 0) -> Array:
	var out: Array = []
	var x := 0
	for e: int in edges:
		out.append(Rect2(x, 0, float(e - x) + overlap, 40))
		x = e
	return out

func _run(label: String, rects: Array) -> void:
	var world := PWorld.new()
	world.sleeping_enabled = false
	world.ccd_enabled = false
	var g := PBody.new()
	g.position = Vector2(-2000.0, 0.0)
	g.make_static()
	world.add_body(g, [_block(4096, 40)])
	g.rects = rects
	g.rects_rev += 1
	g.update_aabb()
	for c in 6:
		for r in 5:
			var b := PBody.new()
			b.position = Vector2(-200.0 + float(c) * 60.0, -7.0 - float(r) * 14.0)
			world.add_body(b, [_block(14, 14)])
	for i in 300:
		world.step(1.0 / 60.0)
	var max_rot := 0.0
	var max_dx := 0.0
	var flipped := 0
	var i2 := 0
	for b2 in world.bodies:
		if b2.is_static:
			continue
		max_rot = maxf(max_rot, absf(b2.rotation))
		max_dx = maxf(max_dx, absf(b2.position.x - (-200.0 + float(i2 / 5) * 60.0)))
		if absf(b2.rotation) > 0.01:
			flipped += 1
		i2 += 1
	print("  %-36s 矩形 %d  最大|rot| %9.6f  最大|dx| %7.3f  翻倒 %d/30" % [label, rects.size(), max_rot, max_dx, flipped])

func _initialize() -> void:
	print("=== 地面矩形布局 vs 堆叠稳定性（箱子在局部 1793~2107）===")
	_run("① 整块 [0,4000]（无接缝）", _split([4000]))
	_run("② 按块那 6 个（接缝 2048/3072/...）", _split([2048, 3072, 3584, 3840, 3968, 4000]))
	var rev := _split([2048, 3072, 3584, 3840, 3968, 4000])
	rev.reverse()
	_run("③ 同上但顺序倒过来", rev)
	_run("④ 6 个但互相重叠 1 像素", _split([2048, 3072, 3584, 3840, 3968, 4000], 1))
	_run("⑤ 2 个（最大行程 [0,3968]+[3968,4000]）", _split([3968, 4000]))
	_run("⑥ 6 个但接缝全在箱子左边", _split([1024, 1536, 1664, 1728, 1760, 4000]))
	_run("⑦ 6 个但接缝处留 1 像素真空隙", _split([2047, 3071, 3583, 3839, 3967, 4000]))
	_run("⑧ 3 个（接缝 2048 与 2049 都贴着箱子）", _split([2048, 2049, 4000]))
	quit(0)

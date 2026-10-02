extends SceneTree
## 岛内图着色能拿到多少并行度？先量一量，再下结论。
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

func _scene(piles: int, per_pile: int, gaps: bool) -> PWorld:
	var world := PWorld.new()
	world.sleeping_enabled = false
	var cols := int(ceil(sqrt(float(piles))))
	for p in piles:
		var gx := (p % cols) * (120.0 if gaps else 90.0)
		var gy := float(p / cols) * 260.0
		var g := PBody.new()
		g.position = Vector2(gx, gy + 140.0)
		g.make_static()
		world.add_body(g, [_block(60, 8)])
		for i in per_pile:
			var b := PBody.new()
			b.position = Vector2(gx + 10.0, gy + 120.0 - i * 16.0)
			world.add_body(b, [_block(14, 14)])
	for i in 120:
		world.step(1.0 / 60.0)
	return world

## 贪心着色：两条流形只要共享刚体就冲突
func _colors(ms: Array) -> Array:
	var by_body := {}
	for i in ms.size():
		for id in [ms[i].a.id, ms[i].b.id]:
			if not by_body.has(id):
				by_body[id] = []
			by_body[id].append(i)
	var order: Array = []
	for i in ms.size():
		order.append(i)
	order.sort_custom(func(x: int, y: int) -> bool:
		return by_body[ms[x].a.id].size() + by_body[ms[x].b.id].size() \
			> by_body[ms[y].a.id].size() + by_body[ms[y].b.id].size())
	var color := {}
	for i: int in order:
		var used := {}
		for id in [ms[i].a.id, ms[i].b.id]:
			for j: int in by_body[id]:
				if j != i and color.has(j):
					used[color[j]] = true
		var c := 0
		while used.has(c):
			c += 1
		color[i] = c
	var hist := {}
	for i: int in color:
		hist[color[i]] = hist.get(color[i], 0) + 1
	return [color.size(), hist]

func _analyze(label: String, world: PWorld) -> void:
	var islands := world._build_islands()
	var biggest := 0
	for isle: Dictionary in islands:
		biggest = maxi(biggest, (isle["manifolds"] as Array).size())
	var total := world.manifolds.size()
	# 全局着色（等于"把岛边界去掉后"的上限）
	var all_c := _colors(world.manifolds)
	var hist: Dictionary = all_c[1]
	var max_class := 0
	for k: int in hist:
		max_class = maxi(max_class, hist[k])
	print("\n%s" % label)
	print("  流形 %d | 岛 %d 个 | 最大岛 %d 条 (=%.0f%% 的工作量只能串行)" % [
		total, islands.size(), biggest, 100.0 * float(biggest) / maxf(1.0, float(total))])
	print("  岛内着色：需要 %d 种颜色 | 最大颜色类 %d 条" % [all_c[0], max_class])
	print("  理论并行度：岛并行 %.2fx  ->  加着色后 %.2f 条同时解" % [
		float(islands.size()), float(max_class)])
	var parts: Array = []
	for k2: int in hist:
		parts.append("c%d:%d" % [k2, hist[k2]])
	parts.sort()
	print("  颜色分布 ", " ".join(parts))

func _initialize() -> void:
	print("=== 岛内图着色：理论并行度实测 ===")
	_analyze("[A] 16 堆 x 5，堆间有间隔", _scene(16, 5, true))
	_analyze("[B] 36 堆 x 5，堆间有间隔", _scene(36, 5, true))
	_analyze("[C] 一堆 60 个（最坏情况）", _scene(1, 60, true))
	quit(0)

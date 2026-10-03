extends SceneTree
## 窄相 A/B：collide() 里那次**多余的 sat()** 到底值多少。
## 旧实现（sat_signed + sat + 裁剪）原样抄一份做对照，新实现在 collide.gd 里。
## 用真实的 OBB 对（从场景里取），并且分别统计"穿透"和"分离"两类。
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

## ---- 旧实现（逐字抄，只为了 A/B）----
static func _old_collide(a, b, margin: float = 0.0) -> Dictionary:
	var s := Collide.sat_signed(a, b)
	var sep: float = s["sep"]
	if sep > margin:
		return {"normal": Vector2.RIGHT, "points": []}
	if sep > 0.0:
		var normal0: Vector2 = s["normal"]
		var pa := Collide.support(a, normal0)
		var pb := Collide.support(b, -normal0)
		return {"normal": normal0, "points": [
			{"position": (pa + pb) * 0.5, "depth": 0.0, "sep": sep, "feature": -1}]}
	var s2 := Collide.sat(a, b)
	if not s2["hit"]:
		return {"normal": Vector2.RIGHT, "points": []}
	var normal: Vector2 = s2["normal"]
	var ref: Collide.OBB = a if s2["ref_is_a"] else b
	var inc: Collide.OBB = b if s2["ref_is_a"] else a
	var ref_normal := normal if s2["ref_is_a"] else -normal
	var ref_edge := 0
	var best_dot := -INF
	for i in 4:
		var d := ref.edge_normal(i).dot(ref_normal)
		if d > best_dot:
			best_dot = d
			ref_edge = i
	var inc_edge := 0
	var worst_dot := INF
	for i in 4:
		var d2 := inc.edge_normal(i).dot(ref_normal)
		if d2 < worst_dot:
			worst_dot = d2
			inc_edge = i
	var rp1: Vector2 = ref.edge_start(ref_edge)
	var rp2: Vector2 = ref.edge_end(ref_edge)
	var ip1: Vector2 = inc.edge_start(inc_edge)
	var ip2: Vector2 = inc.edge_end(inc_edge)
	var tangent: Vector2 = (rp2 - rp1).normalized()
	var seg := Collide._clip_segment(ip1, ip2, -tangent, -tangent.dot(rp1))
	if seg.is_empty():
		return {"normal": normal, "points": []}
	seg = Collide._clip_segment(seg[0], seg[1], tangent, tangent.dot(rp2))
	if seg.is_empty():
		return {"normal": normal, "points": []}
	var base := ref_edge * 16 + inc_edge * 4
	var out: Array = []
	for i in seg.size():
		var p: Vector2 = seg[i]
		var separation: float = (p - rp1).dot(ref_normal)
		if separation <= 0.0:
			out.append({"position": p, "depth": -separation, "sep": separation, "feature": base + i})
	return {"normal": normal, "points": out}

var _pairs: Array = []
var _margin := 2.0
var _pen := 0

func _gather() -> void:
	var world := PWorld.new()
	world.sleeping_enabled = false
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
	# 把这一帧里所有"过了 AABB 粗筛"的矩形对收集起来（含 margin 膨胀）
	world._cache_shapes()
	var bodies := world.bodies
	for ia in bodies.size():
		for ib in range(ia + 1, bodies.size()):
			var A: PBody = bodies[ia]
			var B: PBody = bodies[ib]
			if A.rects.is_empty() or B.rects.is_empty():
				continue
			for ra in A.rects.size():
				var oa = Collide.obb_from_local_rect(A, A.rects[ra])
				var ba: Rect2 = world._obb_aabb(oa).grow(_margin)
				for rb in B.rects.size():
					var ob = Collide.obb_from_local_rect(B, B.rects[rb])
					var bb: Rect2 = world._obb_aabb(ob).grow(_margin)
					if not ba.intersects(bb, true):
						continue
					_pairs.append([oa, ob])
					var s = Collide.sat_signed(oa, ob)
					if float(s["sep"]) <= 0.0:
						_pen += 1

func _time(use_new: bool, reps: int) -> float:
	var best := 1.0e18
	for rep in reps:
		var t0 := Time.get_ticks_usec()
		for pr: Array in _pairs:
			if use_new:
				Collide.collide(pr[0], pr[1], _margin)
			else:
				_old_collide(pr[0], pr[1], _margin)
		var dt := float(Time.get_ticks_usec() - t0)
		best = minf(best, dt)
	return best

func _initialize() -> void:
	_gather()
	print("=== collide() A/B（%d 对矩形，其中 %d 对是穿透/接触）===" % [_pairs.size(), _pen])
	print("margin = %.1f" % _margin)
	var n := _pairs.size()
	var o := _time(false, 7)
	var m := _time(true, 7)
	print("旧(sat_signed+sat): %8.1f us/轮 | 新(只用 sat_signed): %8.1f us/轮 | 新/旧 %.2fx" % [
		o, m, m / maxf(0.01, o)])
	print("每次调用: 旧 %.3f us -> 新 %.3f us" % [o / float(n), m / float(n)])
	quit(0)

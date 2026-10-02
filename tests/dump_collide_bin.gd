extends SceneTree
## 导出真实场景里**所有进入 SAT 的 OBB 对** + GDScript collide 的结果。
## C++ 侧读同一份输入、跑自己的实现，逐个字段比对 —— 先证明数学一致，再谈性能。
## 用法: --script res://tests/dump_collide_bin.gd -- pile:10:8:60
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

func _scene(kind: String) -> PWorld:
	var w := PWorld.new()
	w.sleeping_enabled = false
	w.ccd_enabled = false
	w.use_threads = false
	var parts := kind.split(":")
	var fw := 2000.0
	var g := PBody.new()
	g.position = Vector2(-fw * 0.5, 0.0)
	g.make_static()
	w.add_body(g, [_block(int(fw), 40)])
	match parts[0]:
		"pile":
			for r in int(parts[2]):
				for c in int(parts[1]):
					var b := PBody.new()
					b.position = Vector2(-float(int(parts[1])) * 7.0 + float(c) * 14.0, -7.0 - float(r) * 14.0)
					w.add_body(b, [_block(14, 14)])
		"frag":
			var n := int(parts[1])
			for i in n:
				var f := PBody.new()
				f.position = Vector2(-600.0 + float(i % 50) * 24.0 + 6.0, -500.0 - float(i / 50) * 16.0)
				w.add_body(f, [_block(6, 6)])
				f.linear_velocity = Vector2(-60.0 + float(i % 11) * 12.0, 120.0)
	return w

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var kind := "pile:10:8" if args.is_empty() else args[0]
	var parts := kind.split(":")
	var steps := 60
	if parts.size() >= 4:
		steps = int(parts[3])
	var w := _scene(kind)
	for i in steps:
		w.step(1.0 / 60.0)
	w._cache_shapes()
	var scratch := Collide.Sat.new()
	var pairs: Array = []
	var npts := 0
	var n := w.bodies.size()
	for ia in n:
		var a: PBody = w.bodies[ia]
		if a.rects.is_empty():
			continue
		for ib in range(ia + 1, n):
			var b: PBody = w.bodies[ib]
			if b.rects.is_empty():
				continue
			var rel := (b.linear_velocity - a.linear_velocity).length()
			var spin := absf(a.angular_velocity) * w._radius_cache[ia] \
				+ absf(b.angular_velocity) * w._radius_cache[ib]
			var margin := minf((rel + spin) * (1.0 / 60.0) + 0.5, w.max_speculative_margin)
			for ra in a.rects.size():
				var oa: Collide.OBB = w._obb_cache[ia][ra]
				var box_a: Rect2 = (w._aabb_cache[ia][ra] as Rect2).grow(margin)
				for rb in b.rects.size():
					var ob: Collide.OBB = w._obb_cache[ib][rb]
					var box_b: Rect2 = (w._aabb_cache[ib][rb] as Rect2).grow(margin)
					if not box_a.intersects(box_b, true):
						continue
					var res := Collide.collide(oa, ob, margin, scratch)
					var pts: Array = res["points"]
					pairs.append([oa, ob, margin, res["normal"], pts])
					npts += pts.size()
	print("场景 %s: 导出了 %d 对（其中接触点 %d 个）" % [kind, pairs.size(), npts])
	var f := FileAccess.open("res://gdext/collide_pairs.bin", FileAccess.WRITE)
	f.store_32(pairs.size())
	f.store_32(npts)
	for e: Array in pairs:
		var oa: Collide.OBB = e[0]
		var ob: Collide.OBB = e[1]
		for o in [oa, ob]:
			f.store_double(o.center.x); f.store_double(o.center.y)
			f.store_double(o.u.x); f.store_double(o.u.y)
			f.store_double(o.v.x); f.store_double(o.v.y)
			f.store_double(o.h.x); f.store_double(o.h.y)
		f.store_double(e[2])
		var nrm: Vector2 = e[3]
		f.store_double(nrm.x); f.store_double(nrm.y)
		var pts: Array = e[4]
		f.store_32(pts.size())
		f.store_32(0)
		for i2 in 2:
			if i2 < pts.size():
				var pd: Dictionary = pts[i2]
				var pos: Vector2 = pd["position"]
				f.store_double(pos.x); f.store_double(pos.y)
				f.store_double(pd["depth"]); f.store_double(pd["sep"]); f.store_double(pd["feature"])
			else:
				for k in 5:
					f.store_double(0.0)
	f.close()
	print("已导出 collide_pairs.bin")
	quit(0)

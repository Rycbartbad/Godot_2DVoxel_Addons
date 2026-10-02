extends SceneTree
## 窄相移植探针：同一批配对，GDScript 与原生各算一遍，逐字段对比
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const Solver := preload("res://src/physics/solver.gd")

func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

## 场景要**密集重叠**：稀疏摆放时根本没有几对，
## "全一致"什么都证明不了（第一次就只跑出 5 个流形）。
## 三种布局分别覆盖：深度穿透（裁剪路径）、浅接触、以及带推测边际的接近。
func _build(native: bool, layout: int, seed_v: int, margin: float) -> PWorld:
	var w := PWorld.new()
	w.gravity = Vector2.ZERO
	w.use_native_solve = false
	w.use_native_broadphase = false
	w.use_native_collide = native
	w.max_speculative_margin = margin
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var n := 6
	for gy in n:
		for gx in n:
			var b := PBody.new()
			var step := 14.0 if layout == 0 else (22.0 if layout == 1 else 8.0)
			b.position = Vector2(float(gx) * step, float(gy) * step)
			if layout == 0:
				b.rotation = rng.randf_range(-PI, PI)
			elif layout == 1:
				b.rotation = rng.randf_range(-0.3, 0.3)
			else:
				b.rotation = rng.randf_range(-PI, PI)
				b.linear_velocity = Vector2(rng.randf_range(-300.0, 300.0), rng.randf_range(-300.0, 300.0))
			var sz := 18 if layout != 1 else 26
			w.add_body(b, [_block(sz, sz)])
	return w

func _collect(w: PWorld) -> Dictionary:
	# 只跑一次宽相（不推进），拿到这一帧的全部流形
	w._cache_shapes()
	w._broadphase(1.0 / 60.0)
	var d := {}
	for m: Solver.Manifold in w.manifolds:
		var parts: PackedStringArray = []
		for p: Solver.Point in m.points:
			parts.append("%.12f,%.12f|%.12f|%.12f|%d" % [
				p.position.x, p.position.y, p.depth, p.separation, p.feature_id])
		d[m.key] = "n=%.12f,%.12f;cnt=%d;%s" % [
			m.normal.x, m.normal.y, m.points.size(), ";".join(parts)]
	return d

func _initialize() -> void:
	var total_a := 0
	var total_only_a := 0
	var total_only_b := 0
	var total_diff := 0
	var shown := 0
	for layout in 3:
		for seed_v in [1, 2, 3]:
			for margin in [0.0, 0.5, 1.5]:
				var a := _collect(_build(false, layout, seed_v, margin))
				var b := _collect(_build(true, layout, seed_v, margin))
				total_a += a.size()
				for k in a:
					if not b.has(k):
						total_only_a += 1
						if shown < 3:
							shown += 1
							print("  只 GDScript 有 key=%d  %s" % [k, a[k]])
						continue
					if String(a[k]) != String(b[k]):
						total_diff += 1
						if shown < 3:
							shown += 1
							print("  值不同 key=%d (layout=%d seed=%d margin=%.1f)" % [k, layout, seed_v, margin])
							print("    GS  : %s" % a[k])
							print("    原生: %s" % b[k])
				for k in b:
					if not a.has(k):
						total_only_b += 1
	print("对比了 %d 个 GDScript 流形 | 只在GS: %d | 只在原生: %d | 值不同: %d" % [
		total_a, total_only_a, total_only_b, total_diff])
	quit(0)

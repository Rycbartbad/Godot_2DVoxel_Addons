extends SceneTree
## decompose 原生化前后的实测数字（可复现，不是"某次对话里的一个数"）。
##
## 跑法：
##   godot --headless --path . --script res://tests/bench_decompose_native.gd
##
## 三组：
##   ① 800x40 的 decompose：GDScript 参照实现 vs 原生（各 20 次取最好值）
##      —— 分"热（AABB 缓存新鲜）"与"每笔破坏（AABB 缓存被作废）"两种，
##      因为前者只量块路径，后者才是每笔破坏真正付的钱（差 1.8 ms）。
##   ② 冷路径：全新形状的第一次 decompose（块缓存全空）
##   ③ fracture_pixels 端到端：内部删 (100,20) vs **外围**删 (400,0)
##      （外围那一笔会作废 AABB 缓存 —— 这就是原生化真正省下的东西）
##
## ⚠️ "关掉原生"用的是 GreedyRects 自己的懒加载状态（_raster_checked/_raster），
##    不新增开关 —— 一个只为 benchmark 存在的开关迟早会被别处误用。
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const GreedyRects := preload("res://src/core/greedy_rects.gd")

const N := 20

func _ground(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

## 关掉/打开原生路径（用已有的懒加载状态，见文件头）
func _set_native(on: bool) -> void:
	if on:
		GreedyRects._raster_checked = false
		GreedyRects._raster = null
		GreedyRects._ensure_raster()
	else:
		GreedyRects._raster_checked = true
		GreedyRects._raster = null

## 一个"每笔破坏"循环：每笔删一个像素（AABB 缓存随之作废）再跑一次 decompose。
## 返回最好那一笔的 ms。
func _per_stroke(s: PixelShape, use_gd: bool) -> float:
	s._aabb_rev = -1
	if use_gd:
		GreedyRects.decompose_gd(s, 0)
	else:
		GreedyRects.decompose(s, 0)
	var best := 1e18
	for i in N:
		s.clear_pixel(400 + i, 0)
		var t := Time.get_ticks_usec()
		if use_gd:
			GreedyRects.decompose_gd(s, 0)
		else:
			GreedyRects.decompose(s, 0)
		var d := float(Time.get_ticks_usec() - t) / 1000.0
		if d < best:
			best = d
	return best

## 热：AABB 缓存新鲜时连跑 N 次
func _warm(s: PixelShape, use_gd: bool) -> float:
	var best := 1e18
	for i in N:
		var t := Time.get_ticks_usec()
		if use_gd:
			GreedyRects.decompose_gd(s, 0)
		else:
			GreedyRects.decompose(s, 0)
		var d := float(Time.get_ticks_usec() - t) / 1000.0
		if d < best:
			best = d
	return best

## 冷：每次一个全新形状（造形状的钱不算在内），量第一次 decompose
func _cold(use_gd: bool) -> float:
	var shapes: Array = []
	for i in N:
		shapes.append(_ground(800, 40))
	var best := 1e18
	for i in N:
		var t := Time.get_ticks_usec()
		if use_gd:
			GreedyRects.decompose_gd(shapes[i], 0)
		else:
			GreedyRects.decompose(shapes[i], 0)
		var d := float(Time.get_ticks_usec() - t) / 1000.0
		if d < best:
			best = d
	return best

## fracture_pixels 端到端：每个样本一个全新的世界（与 tests/diag_fpx_breakdown.gd 同口径）
func _fracture(px: Vector2i) -> float:
	var best := 1e18
	for i in N:
		var w := PWorld.new()
		w.gravity = Vector2.ZERO
		var b := PBody.new()
		w.add_body(b, [_ground(800, 40)])
		var t := Time.get_ticks_usec()
		w.fracture_pixels(b, {b.shapes[0]: {px: true}}, 0.0, true)
		var d := float(Time.get_ticks_usec() - t) / 1000.0
		if d < best:
			best = d
	return best

func _initialize() -> void:
	print("=== decompose 原生化实测（800x40，各 %d 次取最好值，单位 ms）===" % N)
	var s1 := _ground(800, 40)
	var s2 := _ground(800, 40)
	_set_native(false)
	print("① 热（AABB 缓存新鲜，只量块路径）")
	print("     GDScript decompose_gd   %7.3f" % _warm(s1, true))
	_set_native(true)
	print("     原生     decompose      %7.3f" % _warm(s2, false))
	_set_native(false)
	print("② 每笔破坏（每笔删一个顶边像素，AABB 缓存被作废）")
	print("     GDScript decompose_gd   %7.3f" % _per_stroke(s1, true))
	_set_native(true)
	print("     原生     decompose      %7.3f" % _per_stroke(s2, false))
	_set_native(false)
	print("③ 冷路径（全新形状的第一次调用，块缓存全空）")
	print("     GDScript decompose_gd   %7.3f" % _cold(true))
	_set_native(true)
	print("     原生     decompose      %7.3f" % _cold(false))
	print("")
	print("=== fracture_pixels 端到端（800x40，每个样本一个全新世界）===")
	for spec in [[Vector2i(100, 20), "内部 删(100,20)"], [Vector2i(400, 0), "外围 删(400,0)"]]:
		_set_native(false)
		var t_off := _fracture(spec[0])
		_set_native(true)
		var t_on := _fracture(spec[0])
		print("  %-16s 原生关 %7.3f -> 原生开 %7.3f   （省 %6.3f）" % [spec[1], t_off, t_on, t_off - t_on])
	print("")
	print("=== 结果正确性自检（原生 vs 参照，逐位）===")
	var chk := _ground(800, 40)
	var a: GreedyRects.Result = GreedyRects.decompose(chk, 64)
	var b2: GreedyRects.Result = GreedyRects.decompose_gd(chk, 64)
	var same := a.rects.size() == b2.rects.size() and a.origin == b2.origin \
			and a.budget_exceeded == b2.budget_exceeded
	if same:
		for i in a.rects.size():
			if a.rects[i] != b2.rects[i]:
				same = false
				break
	print("  800x40：%d 个矩形，逐位相同 = %s" % [a.rects.size(), str(same)])
	quit(0)

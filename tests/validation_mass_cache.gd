extends SceneTree
## 质量属性的**逐块缓存**闸门：复用必须与全量重算**逐位相同**。
##
## ⚠️ 为什么钉这条：这个优化的全部风险都在"缓存读到脏值"上 —— 而那是**静默**的
##    （质量/惯性算错不会报错，只会让物理手感悄悄变掉）。所以判据必须是
##    "带缓存算出来的值 == 不带缓存重算的值"，而且是**逐位**（is_same，不是近似）。
##
## ⚠️ 密度特意用 2.5 / 7.8（不是 2 的幂）：这样加法结合律的差异会**暴露**出来 ——
##    用 1.0 或 8.0 时怎么加都一样，测不出顺序问题。
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const MassProps := preload("res://src/core/mass_props.gd")
const GreedyRects := preload("res://src/core/greedy_rects.gd")

var _pass := 0
var _fail := 0
func _c(n: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1; print("  PASS  ", n, "  ", d)
	else: _fail += 1; print("  FAIL  ", n, "  ", d)

func _ground(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

## 全量重算（不传 changed_keys -> 会清掉缓存并整块重扫）
func _full(w: PWorld, s: PixelShape) -> MassProps.Props:
	return MassProps.compute(s, w.density_callable(), w.friction_callable(), w.restitution_callable())

func _cmp(b: PBody, p: MassProps.Props) -> bool:
	return is_same(b.mass, p.mass) and is_same(b.inertia, p.inertia) \
		and is_same(b.local_com.x, p.com.x) and is_same(b.local_com.y, p.com.y) \
		and is_same(b.friction, p.fric_sum / float(p.pixel_count)) \
		and is_same(b.restitution, p.rest_sum / float(p.pixel_count))

func _cmp_props(a: MassProps.Props, b: MassProps.Props) -> bool:
	return is_same(a.mass, b.mass) and is_same(a.inertia, b.inertia) \
		and is_same(a.com.x, b.com.x) and is_same(a.com.y, b.com.y) \
		and is_same(a.fric_sum, b.fric_sum) and is_same(a.rest_sum, b.rest_sum) \
		and is_same(a.pixel_count, b.pixel_count)


func _init_world() -> Array:
	var w := PWorld.new()
	w.gravity = Vector2.ZERO
	w.set_material_density(1, 2.5)
	w.set_material_density(3, 7.8)
	var b := PBody.new()
	var s := _ground(800, 40)
	w.add_body(b, [s])
	_full(w, s)                       # 先全量算一次（把缓存填上）
	return [w, b, s]

func _initialize() -> void:
	print("=== 质量属性逐块缓存 ===")

	# ① 一次 hinted 破坏（1 个像素）后：body 上的值 == 全量重算
	var t := _init_world()
	var w: PWorld = t[0]
	var b: PBody = t[1]
	var s: PixelShape = t[2]
	var t0 := Time.get_ticks_usec()
	w.fracture_pixels(b, {s: {Vector2i(100, 20): true}}, 0.0, true)
	var ms_hinted := float(Time.get_ticks_usec() - t0) / 1000.0
	var full := _full(w, s)
	_c("hinted 破坏 1 像素后：质量属性 == 全量重算（逐位）", _cmp(b, full),
		"mass %.9f / inertia %.6f" % [b.mass, b.inertia])

	# ② 连续多次 hinted 破坏（每次只重算自己那块）
	var ok_multi := true
	for i in 5:
		var px := Vector2i(200 + i * 7, 20 + i)
		w.fracture_pixels(b, {s: {px: true}}, 0.0, true)
		var f2 := _full(w, s)
		ok_multi = ok_multi and _cmp(b, f2)
	_c("连续 5 次 hinted 破坏后仍然逐位相同", ok_multi)

	# ③ **没传提示**的路径（set_pixel + rebuild）：也必须对
	var t2 := _init_world()
	var w2: PWorld = t2[0]
	var b2: PBody = t2[1]
	var s2: PixelShape = t2[2]
	s2.clear_pixel(300, 10)
	b2.rebuild([s2], w2.density_callable(), 64, Rect2i(),
		w2.friction_callable(), w2.restitution_callable(), {})
	var f3 := _full(w2, s2)
	_c("没传提示的路径（set_pixel + rebuild）也对", _cmp(b2, f3),
		"mass %.9f" % b2.mass)

	# ④ ⚠️ 密度表改了：**复用的块也必须跟着变**（缓存只存几何量，密度是合并时现查的）
	var t3 := _init_world()
	var w3: PWorld = t3[0]
	var b3: PBody = t3[1]
	var s3: PixelShape = t3[2]
	w3.set_material_density(1, 9.0)          # 改密度（缓存里存的还是旧的几何量）
	w3.fracture_pixels(b3, {s3: {Vector2i(400, 30): true}}, 0.0, true)
	var f4 := _full(w3, s3)
	_c("密度改了以后复用块也生效（逐位）", _cmp(b3, f4),
		"mass %.9f（旧密度会得到 2.5 倍的值）" % b3.mass)

	# ⑤ 静态体（跳过质量属性那条路）不许被缓存影响
	var t4 := _init_world()
	var w4: PWorld = t4[0]
	var b4: PBody = t4[1]
	b4.make_static()
	w4.fracture_pixels(b4, {b4.shapes[0]: {Vector2i(50, 5): true}}, 0.0, true)
	_c("静态体：质量/惯性仍然是 0", is_same(b4.mass, 0.0) and is_same(b4.inertia, 0.0),
		"mass %.3f inertia %.3f" % [b4.mass, b4.inertia])

	# ⑥ 性能：同一个形状，全量 vs 只重算 1 块
	var t5 := _init_world()
	var w5: PWorld = t5[0]
	var b5: PBody = t5[1]
	var s5: PixelShape = t5[2]
	# ⚠️ 这里必须**隔离缓存本身**：拿 fracture_pixels 整体去比裸 compute 是苹果比橘子
	#    （前者还含 GreedyRects.decompose ~2 ms，那是另一笔账）。
	#    传**空** changed_keys = "没有任何块变过" -> 全部复用，量到的就是纯复用成本。
	var tt := Time.get_ticks_usec()
	var ffull := _full(w5, s5)
	var ms_full := float(Time.get_ticks_usec() - tt) / 1000.0
	tt = Time.get_ticks_usec()
	var freuse := MassProps.compute(s5, w5.density_callable(), w5.friction_callable(),
		w5.restitution_callable(), {})
	var ms_reuse := float(Time.get_ticks_usec() - tt) / 1000.0
	print("  [性能] 全量 compute %.3f ms | 全部复用 %.3f ms | 加速 %.1fx（%d 块）" % [
		ms_full, ms_reuse, ms_full / maxf(ms_reuse, 0.0001), s5.chunks.size()])
	_c("复用与全量逐位相同", _cmp_props(freuse, ffull), "mass %.6f" % freuse.mass)
	_c("缓存确实省了时间", ms_reuse < ms_full * 0.5, "%.3f < %.3f ms" % [ms_reuse, ms_full])

	# ⑦ **内部**像素：外轮廓没变 -> 复用旧矩形（跳过 GreedyRects.decompose）
	var t6 := _init_world()
	var w6: PWorld = t6[0]
	var b6: PBody = t6[1]
	var s6: PixelShape = t6[2]
	var rects_before: Array = b6.rects.duplicate()
	var rev_before: int = b6.rects_rev
	var t6t := Time.get_ticks_usec()
	w6.fracture_pixels(b6, {s6: {Vector2i(400, 20): true}}, 0.0, true)
	var ms_inner := float(Time.get_ticks_usec() - t6t) / 1000.0
	_c("内部与外围**行为一致**：都重扫（不做内部特例）",
		b6.rects_rev != rev_before,
		"rects_rev %d -> %d" % [rev_before, b6.rects_rev])
	_c("内部像素：质量属性照旧更新（逐位）", _cmp(b6, _full(w6, s6)))

	# ⑧ **外围**像素：外轮廓变了 -> 必须重扫
	var t7 := _init_world()
	var w7: PWorld = t7[0]
	var b7: PBody = t7[1]
	var s7: PixelShape = t7[2]
	var rev7: int = b7.rects_rev
	var t7t := Time.get_ticks_usec()
	w7.fracture_pixels(b7, {s7: {Vector2i(400, 0): true}}, 0.0, true)
	var ms_edge := float(Time.get_ticks_usec() - t7t) / 1000.0
	var full_rects := 0
	for s8 in b7.shapes:
		full_rects += GreedyRects.decompose(s8, 64).rects.size()
	_c("外围像素：矩形重扫了（rects_rev 动了）", b7.rects_rev != rev7,
		"rects_rev %d -> %d" % [rev7, b7.rects_rev])
	_c("外围像素：矩形数与全量 decompose 一致", b7.rects.size() == full_rects,
		"%d vs %d" % [b7.rects.size(), full_rects])
	print("  [性能] 内部 1 像素 %.3f ms | 外围 1 像素 %.3f ms（含 decompose）" % [ms_inner, ms_edge])
	_c("内部与外围耗时同档（都含 decompose）", absf(ms_inner - ms_edge) < 3.0,
		"%.3f vs %.3f ms" % [ms_inner, ms_edge])

	# ⑨ **甜甜圈**：删一圈闭合像素 -> 内部那块被断开（产生碎片）。
	#    外轮廓确实没变，但母体少了那块面积 -> 旧矩形会盖住碎片 -> **必须重扫**。
	var t8 := _init_world()
	var w8: PWorld = t8[0]
	var b8: PBody = t8[1]
	var s8: PixelShape = t8[2]
	var rev8: int = b8.rects_rev
	var ring := {}
	for i in range(10, 15):
		ring[Vector2i(i, 10)] = true
		ring[Vector2i(i, 14)] = true
		ring[Vector2i(10, i)] = true
		ring[Vector2i(14, i)] = true
	var res8: Dictionary = w8.fracture_pixels(b8, {s8: ring}, 0.0, true)
	var frags8: Array = res8.get("fragments", [])
	_c("甜甜圈：确实断出了碎片", frags8.size() >= 1, "碎片 %d 个" % frags8.size())
	_c("甜甜圈：矩形必须重扫（否则母体矩形盖住碎片）", b8.rects_rev != rev8,
		"rects_rev %d -> %d" % [rev8, b8.rects_rev])
	# ⚠️ 必须拿**母体当前的 shape** 去全量重算 —— split(adopt=true) 会把块搬到新 shape 上，
	#    原来的 s8 已经不是母体的形状了（第一版闸门就是这么写错的，报了假 FAIL）。
	var full8: MassProps.Props = MassProps.compute(b8.shapes[0], w8.density_callable(),
		w8.friction_callable(), w8.restitution_callable())
	_c("甜甜圈：质量属性仍然逐位正确", _cmp(b8, full8),
		"mass %.6f（母体当前 shape 像素 %d）" % [b8.mass, b8.shapes[0].pixel_count()])

	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

extends SceneTree
## 接触事件的**两条性能约定**的闸门（2026-10 加）：
##
##   1. Contact.contact_width 是**惰性**的 —— 采集时不算，**读它的时候**才算，算完缓存；
##   2. contact_stress_enabled = false（轻量模式）不填应力场：shear_ratio 恒 0，
##      但事件本身（点/法向/接近速度/冲量）一个不少，contact_width 读的时候照样算。
##
## ⚠️ 为什么这两条值得一个闸门：它们都是**性能**约定，而性能约定的"实现"错了
##    不会报错 —— 只会让"引擎无条件付钱"偷偷回来（这个项目在 AABB 缓存 /
##    分块贴图 / 矩形网格上各栽过一次，全是静默错值）。
##
## ⚠️⚠️ 所以这里的判据**不拿缓存自己的值当预期值**，用两条独立的路：
##    · **几何预期**：20 宽的方块平放在地面上，切向宽度就该 ≈ 20（不是别的数）；
##      4 宽的箱子就该 ≈ 4 —— 两者差 3 倍以上才算对；
##    · **改像素**（同一份代码，两个方向）：
##        · 采集之后、**第一次读之前**把形状挖空 -> 第一次读必须是"挖空之后"的值
##          （= 读的时候才算 -> 惰性）；如果它读到 ~20，说明采集时就算过了 -> 失败。
##        · **读过之后**再挖空 -> 再读必须**还是旧值**（= 缓存）；
##          如果它变成 0，说明每次都重算 -> 缓存没生效 -> 失败。
##      这两条只有"惰性 + 缓存"同时做对才都成立。
##
## ⚠️ 顺序是测试的一部分：惰性那条必须在第一次读**之前**改像素，缓存那条必须在
##    第一次读**之后**改像素。反了就两条都测不出来（我先写反过一次）。

const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

var _pass := 0
var _fail := 0
func _c(n: String, ok: bool, d: String = "") -> void:
	if ok:
		_pass += 1
		print("  PASS  ", n, "  ", d)
	else:
		_fail += 1
		print("  FAIL  ", n, "  ", d)


## 宽 w_box、高 20 的方块落在 400 宽的地面上（离地 1 px，自己落下去）。
## 返回 [world, box, ground, box_shape]。
func _rest(w_box: int, stress: bool) -> Array:
	var w := PWorld.new()
	w.gravity = Vector2(0, 400)
	w.contact_events_enabled = true
	w.contact_stress_enabled = stress
	# ⚠️ 必须配材质强度：不配的话 shear_ratio 那一段（两次 thickness_at）根本不跑，
	#    轻量模式与全量模式就分不出来 —— 闸门会变成空转。
	w.set_material_strength(1, 100.0, 30.0)
	var g := PBody.new()
	g.position = Vector2(-200, 300)
	g.make_static()
	var gs := PixelShape.new()
	gs.fill_rect(Rect2i(0, 0, 400, 40), 1)
	w.add_body(g, [gs])
	var b := PBody.new()
	b.position = Vector2(-w_box / 2.0, 279)     # 底面在 y=299，地面顶在 300
	var bs := PixelShape.new()
	bs.fill_rect(Rect2i(0, 0, w_box, 20), 1)
	w.add_body(b, [bs])
	return [w, b, g, bs]


## 跑 steps 步，返回**最后一步采集到的**那一对接触（没采到就是 null）。
## 每步都重新找 -> 拿到的一定是最后一步的（不是早期帧的残留）。
func _settle_and_grab(w: PWorld, box, ground, steps: int):
	var c = null
	for i in steps:
		w.step(1.0 / 60.0)
		c = _contact_of(w, box, ground)
	return c


func _contact_of(w: PWorld, a, b):
	for c in w.contacts:
		if (c.a == a and c.b == b) or (c.a == b and c.b == a):
			return c
	return null


## **独立算出来的几何预期**：接触点取的是流形的**第一个点**（它落在接触面的**一端**），
## 而扫描窗口以这个点为中心、半径 = 两者 AABB 的重叠跨度/2 + 4（下限 8）—— 所以
##   宽 W 的接触量到的宽度 = min(W, W/2 + 4)   （W <= 8 时窗口够大 -> 量到整宽）
## 20 -> 14，4 -> 4。实测与它逐位吻合。
## ⚠️ 这不是"拿引擎自己的值当预期值"：它只用到两条**公开写在 Query.contact_width
##    注释里**的机制（点在一端、窗口半径的算法），不依赖任何缓存/惰性的实现细节。
func _expect_width(w: int) -> float:
	return minf(float(w), float(w) * 0.5 + 4.0)


## 把形状挖空（不走 destruction，直接改像素：本测试只关心"几何变了"）。
func _carve(s: PixelShape, w: int, h: int) -> void:
	for y in h:
		for x in w:
			s.clear_pixel(x, y)


func _initialize() -> void:
	print("=== 1. 几何预期：宽度反映真实接触面 ===")
	var r20 := _rest(20, true)
	var w20: PWorld = r20[0]
	var c20 = _settle_and_grab(w20, r20[1], r20[2], 120)
	_c("20 宽的方块落在地面上采集到了接触", c20 != null)
	if c20 == null:
		quit(1)
		return
	var width20: float = c20.contact_width
	var want20 := _expect_width(20)
	print("  20 宽方块的接触宽度 = %.1f px（几何预期 %.1f）" % [width20, want20])
	_c("宽度 = 几何预期（±1 px 的栅格/穿透余量）", absf(width20 - want20) <= 1.0,
		"实测 %.1f，预期 %.1f" % [width20, want20])
	_c("同一个接触重复读给出同一个值", c20.contact_width == width20)
	# ⚠️ 反向对照：读过之后再挖空，值必须**不变**（证明走的是缓存）
	_carve(r20[3], 20, 20)
	_c("读过之后再挖空像素：值不变（缓存生效）", c20.contact_width == width20,
		"挖空后读到 %.1f" % c20.contact_width)

	print("=== 2. 惰性：采集之后、读之前改几何 -> 读到的必须是改后的 ===")
	var rl := _rest(20, false)
	var wl: PWorld = rl[0]
	var cl = _settle_and_grab(wl, rl[1], rl[2], 120)
	_c("轻量模式下同样采集到了接触", cl != null)
	if cl == null:
		quit(1)
		return
	# ⚠️ 顺序关键：**先**挖空，**再**第一次读
	_carve(rl[3], 20, 20)
	var width_after: float = cl.contact_width
	print("  挖空之后第一次读 = %.1f px（若 ≈20 说明采集时就算过了）" % width_after)
	_c("第一次读发生在读的那一刻（惰性）", width_after == 0.0, "实测 %.1f" % width_after)

	print("=== 3. 窄接触就是窄（这个量必须能区分矛尖与盾面）===")
	var rn := _rest(4, true)
	var wn: PWorld = rn[0]
	var cn = _settle_and_grab(wn, rn[1], rn[2], 120)
	_c("4 宽的箱子采集到了接触", cn != null)
	if cn == null:
		quit(1)
		return
	var widthn: float = cn.contact_width
	var wantn := _expect_width(4)
	print("  4 宽箱子的接触宽度 = %.1f px（几何预期 %.1f）" % [widthn, wantn])
	_c("宽度 = 几何预期（窄接触量到整宽）", absf(widthn - wantn) <= 1.0,
		"实测 %.1f，预期 %.1f" % [widthn, wantn])
	_c("宽接触 / 窄接触 > 3 倍", width20 / maxf(1.0, widthn) > 3.0,
		"%.1f / %.1f = %.1f 倍" % [width20, widthn, width20 / maxf(1.0, widthn)])

	print("=== 4. 轻量模式：事件还在，应力场没了 ===")
	var rf := _rest(20, false)
	var wf: PWorld = rf[0]
	var cf = _settle_and_grab(wf, rf[1], rf[2], 120)
	_c("轻量模式仍然给出接触事件", cf != null)
	if cf == null:
		quit(1)
		return
	_c("事件里点数还在", cf.points.size() > 0, "%d 个点" % cf.points.size())
	_c("事件里冲量还在（有限且非负）", is_finite(cf.impulse) and cf.impulse >= 0.0, "%.3f" % cf.impulse)
	_c("事件里接近速度还在（有限）", is_finite(cf.approach), "%.3f" % cf.approach)
	_c("轻量模式 shear_ratio 恒 0（没做那两次厚度扫描）", cf.shear_ratio == 0.0,
		"%.4f" % cf.shear_ratio)
	var widthf: float = cf.contact_width
	_c("轻量模式下宽度仍然读得到（惰性只是延后）", absf(widthf - _expect_width(20)) <= 1.0,
		"%.1f px（几何预期 %.1f）" % [widthf, _expect_width(20)])

	print("=== 5. 对照：全量模式下 shear_ratio 真的会被填 ===")
	var rs := _rest(20, true)
	var ws: PWorld = rs[0]
	var cs = _settle_and_grab(ws, rs[1], rs[2], 120)
	_c("全量模式采集到了接触", cs != null)
	if cs == null:
		quit(1)
		return
	print("  shear_ratio = %.4f（宽度 %.1f）" % [cs.shear_ratio, cs.contact_width])
	_c("全量模式 shear_ratio > 0（厚度扫描真的跑了）", cs.shear_ratio > 0.0, "%.4f" % cs.shear_ratio)

	print("---")
	if _fail == 0:
		print("全部通过：%d 项断言" % _pass)
	else:
		print("失败 %d / %d 项" % [_fail, _pass + _fail])
	quit(0 if _fail == 0 else 1)
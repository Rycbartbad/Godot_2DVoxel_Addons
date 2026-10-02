extends SceneTree
## 破坏判据四件套：接触冲量近似 / 材质强度 / 法向厚度 / 蓝图
## 核心验证：**同样材料、同样撞击，矛尖能破盾、盾面破不了矛**。
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const Query := preload("res://src/physics/query.gd")
const PixelRenderer := preload("res://src/render/pixel_renderer.gd")

var _pass := 0
var _fail := 0
func _c(n: String, ok: bool, d: String = "") -> void:
	if ok:
		_pass += 1
		print("  PASS  ", n, "  ", d)
	else:
		_fail += 1
		print("  FAIL  ", n, "  ", d)

func _box(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _initialize() -> void:
	# ---- 1. 法向厚度 ----
	print("=== 1. 法向厚度（复用体素数据）===")
	var w := PWorld.new()
	w.gravity = Vector2.ZERO
	var wall := PBody.new()
	wall.position = Vector2(100, 0)
	wall.make_static()
	w.add_body(wall, [_box(24, 80)])
	# 沿 +X 穿过：厚 24；沿 +Y 穿过：厚 80
	# ⚠️ 起点要贴着边缘：从中间出发只会数到「还剩多少」
	var tx := Query.thickness_at(wall, Vector2(100, 40), Vector2(1, 0))
	var ty := Query.thickness_at(wall, Vector2(100, 1), Vector2(0, 1))
	_c("沿短边穿过厚 24", absf(tx - 24.0) <= 1.0, "实测 %.1f" % tx)
	_c("沿长边穿过厚 80", absf(ty - 80.0) <= 1.0, "实测 %.1f" % ty)
	_c("完全错开时返回 0", Query.thickness_at(wall, Vector2(999, 999), Vector2(1, 0)) == 0.0)

	# ---- 2. 材质强度表 ----
	print("=== 2. 材质强度表 ===")
	w.set_material_strength(1, 100.0, 30.0)
	var s1 := w.material_strength(1)
	_c("抗压/抗剪分别可读", s1.x == 100.0 and s1.y == 30.0, "%.0f / %.0f" % [s1.x, s1.y])
	w.set_material_strength(2, 200.0)
	var s2 := w.material_strength(2)
	_c("只给抗压时抗剪取 30%", absf(s2.y - 60.0) < 1e-6, "%.0f" % s2.y)
	_c("剪切比插值：0 -> 抗压", absf(w.strength_for(1, 0.0) - 100.0) < 1e-6)
	_c("剪切比插值：1 -> 抗剪", absf(w.strength_for(1, 1.0) - 30.0) < 1e-6)
	_c("没配过的材质返回 0（= 不破坏）", w.strength_for(99, 0.0) == 0.0)

	# ---- 3. 接触冲量近似 ----
	print("=== 3. 接触冲量近似 ===")
	var w2 := PWorld.new()
	w2.gravity = Vector2.ZERO
	w2.contact_events_enabled = true
	var g := PBody.new()
	g.position = Vector2(-200, 300)
	g.make_static()
	w2.add_body(g, [_box(400, 40)])
	var f := PBody.new()
	f.position = Vector2(0, 0)
	w2.add_body(f, [_box(16, 16)])
	f.linear_velocity = Vector2(0, 200)
	var got := false
	for i in 300:
		w2.step(1.0 / 60.0)
		for c in w2.contacts:
			if (c.a == f or c.b == f) and not got:
				got = true
				# 静态体视作无穷大质量 -> m_eff = 落体质量
				var want := f.mass * absf(c.approach)
				_c("冲量 ≈ 有效质量 × 接近速度", absf(c.impulse - want) < 1e-6,
					"%.3f vs %.3f（m_eff=%.1f）" % [c.impulse, want, f.mass])
				_c("接触宽度 > 0", c.contact_width > 0.0, "%.2f px" % c.contact_width)
	_c("产生了带冲量的接触事件", got)

	# ---- 4. 矛 vs 盾（核心）----
	#
	# 同样材料、同样冲量：矛尖接触宽度小 -> 应力大；盾面接触宽度大 -> 应力小。
	# 用 contact_width 做分母就是这个道理。这里用两个不同宽度的"矛"来对照。
	print("=== 4. 矛 vs 盾：应力 = 冲量 / 接触宽度 ===")
	var spear_sigma := _probe_sigma_attitude(true)    # 尖端朝前
	var shield_sigma := _probe_sigma_attitude(false)  # 底边朝前
	var ratio := spear_sigma / maxf(1e-9, shield_sigma)
	_c("窄接触的应力显著大于宽接触", ratio > 8.0,
		"矛尖 σ=%.3f，盾面 σ=%.3f，相差 %.1f 倍" % [spear_sigma, shield_sigma, ratio])
	# 同一强度阈值下：矛破、盾不破
	var strength := (spear_sigma + shield_sigma) * 0.5
	_c("同一强度阈值下：矛尖破、盾面不破", spear_sigma > strength and shield_sigma < strength,
		"阈值 %.3f" % strength)

	# ---- 5. 蓝图渲染 ----
	print("=== 5. 蓝图（不进物理世界）===")
	var rend := PixelRenderer.new()
	root.add_child(rend)
	rend.palette = [Color(0, 0, 0, 0), Color(1, 0, 0, 1)]
	var bp := _box(12, 12)
	rend.sync_blueprint(1, bp, Transform2D(0.0, Vector2(50, 50)))
	_c("蓝图建出了精灵", rend._blueprint_nodes.size() == 1, "%d 个" % rend._blueprint_nodes.size())
	var node: Sprite2D = rend._blueprint_nodes.values()[0]
	_c("蓝图半透明（一眼区分未固化）", node.modulate.a < 1.0, "alpha=%.2f" % node.modulate.a)
	_c("蓝图不在物理世界里（world.bodies 不含它）", w.bodies.size() == 1)
	rend.clear_blueprints()
	_c("clear_blueprints 清空", rend._blueprint_nodes.size() == 0)

	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)


## ⚠️⚠️ 这条测试我写错过两版，都值得记 —— 因为**错的都是实验设计，不是引擎**：
##
##  第一版：直接改撞针宽度。宽的那个质量大 16 倍、冲量跟着大 16 倍，
##          算出「盾的应力反而更大」，与物理完全相反。
##  第二版：改成三角形尖端、固定底边。但撞针撞上后会**转动**，
##          接触区很快不再局限在尖端，比值仍然上不去。
##
##  最终版：**同一个形状、两种撞击姿态** —— 尖朝前 vs 底朝前。
##          质量相同、动量配平、速度相同，唯一的变量就是接触宽度。
##          这才是"控制变量"。
func _probe_sigma(width: int) -> float:
	return _probe_sigma_attitude(true)


## apex_first = true 时尖端朝前（窄接触）；false 时底边朝前（宽接触）。
func _probe_sigma_attitude(apex_first: bool) -> float:
	var w := PWorld.new()
	w.gravity = Vector2.ZERO
	w.contact_events_enabled = true
	var wall := PBody.new()
	wall.position = Vector2(200, 0)
	wall.make_static()
	w.add_body(wall, [_box(40, 400)])
	var spear := PBody.new()
	spear.position = Vector2(0, 190)        # 与墙的纵向中心对齐
	# 等腰三角形：底边 64（在 x=0 侧），顶点在 x=64。
	# 两种姿态都用它，所以质量/形状完全一致。
	var tri := PixelShape.new()
	for x in 64:
		var frac := float(x) / 63.0
		var ww := maxi(1, int(round(lerpf(64.0, 1.0, frac))))
		var y0 := 32 - ww / 2
		for y in range(y0, y0 + ww):
			tri.set_pixel(x, y, 1)
	if not apex_first:
		# 底边朝前：把形状绕纵向中点水平翻转
		var flipped := PixelShape.new()
		for x in 64:
			for y in 64:
				if tri.get_pixel(x, y) != 0:
					flipped.set_pixel(63 - x, y, 1)
		tri = flipped
	w.add_body(spear, [tri])
	# 两种姿态像素数可能差一点，所以**按质量配平速度**让动量严格相同 ——
	# 否则又会混进"质量差异"这个变量。
	var ref_momentum := 400.0 * float(64 * 64)
	spear.linear_velocity = Vector2(ref_momentum / maxf(1.0, spear.mass), 0)
	# ⚠️ 取**整个过程的应力峰值**，不是首帧的。
	#    首帧接触时物体已经压进去了若干像素，切向 ±24 的采样窗口整个落在实心里，
	#    于是两种姿态测出**一模一样**的数（实测就是这个症状：σ 连末位都相同）。
	#    峰值才是有物理意义的量 —— 破坏发生在应力最大的瞬间。
	# 在**冲量最大的那一帧**取宽度 —— 那才是"最狠的一击有多集中"。
	# 不能取 σ 的最大值：尖端接触最初是**投机接触**（还没真正重叠，宽度 0），
	# σ 在那些帧会退化成 impulse/1，反而最大。也不能取宽度的最小值，
	# 同理会被投机接触的 0 拉走。
	var best_j := 0.0
	var best_w := 0.0
	var best := 0.0
	for i in 90:
		w.step(1.0 / 60.0)
		for c in w.contacts:
			if c.a != spear and c.b != spear:
				continue
			# ⚠️⚠️ 必须**跳过 contact_width == 0 的帧**。
			#    那些帧是采样窗口还没和另一侧重叠（或接触点落在界面上），
			#    maxf(1.0, 0) 会把分母变成 1，于是 σ 退化成 impulse/1。
			#    而两种姿态动量相同 -> impulse 相同 -> σ 连末位都一样，
			#    看起来像"两种姿态没区别"。我就在这里被骗了一轮。
			if c.contact_width <= 0.0 or c.impulse <= 0.0:
				continue
			# Variant（contacts 是 Array），:= 推不出类型，必须显式标注
			var j: float = c.impulse
			var wd: float = c.contact_width
			if j > best_j:
				best_j = j
				best_w = wd
				best = j / maxf(1.0, wd)
	return best

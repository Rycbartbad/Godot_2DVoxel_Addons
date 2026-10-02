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
	var spear_sigma := _probe_sigma(4)      # 4 像素宽的矛尖
	var shield_sigma := _probe_sigma(64)    # 64 像素宽的盾面
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


## 造一个「尖端宽度 = width、底边固定 64」的撞针，撞墙后返回接触应力。
##
## ⚠️ 关键是**控制变量**：必须是「同样动量、不同接触面积」。
##    第一版我直接改整体宽度，结果宽的那个质量也大 16 倍、冲量跟着大 16 倍，
##    算出「盾的应力反而更大」—— 那是测试设计错了，不是引擎错了。
##    这里用**等腰三角形尖端**：底边固定 64（质量相同），只改尖端宽度。
func _probe_sigma(width: int) -> float:
	var w := PWorld.new()
	w.gravity = Vector2.ZERO
	w.contact_events_enabled = true
	var wall := PBody.new()
	wall.position = Vector2(200, 0)
	wall.make_static()
	w.add_body(wall, [_box(40, 400)])
	var spear := PBody.new()
	spear.position = Vector2(0, 190)        # 与墙的纵向中心对齐
	var len := 64
	var tip := PixelShape.new()
	for x in len:
		var frac := float(x) / float(len - 1)
		var ww := int(lerpf(float(width), 64.0, frac))
		var y0 := 32 - ww / 2
		for y in range(y0, y0 + maxi(1, ww)):
			tip.set_pixel(x, y, 1)
	w.add_body(spear, [tip])
	# ⚠️ 把**动量配平**：尖端越细，像素越少、质量越小。不补偿的话冲量会跟着小，
	#    又变成"测质量"而不是"测接触面积"。这里让 m*v 恒定。
	var ref_momentum := 400.0 * float(64 * 64)     # 以 64x64 满块为基准
	spear.linear_velocity = Vector2(ref_momentum / maxf(1.0, spear.mass), 0)
	for i in 60:
		w.step(1.0 / 60.0)
		for c in w.contacts:
			if (c.a == spear or c.b == spear) and c.impulse > 0.0:
				return c.impulse / maxf(1.0, c.contact_width)
	return 0.0

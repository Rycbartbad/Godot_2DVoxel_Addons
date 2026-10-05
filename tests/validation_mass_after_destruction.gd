extends SceneTree
## **破坏之后的材质属性**闸门（表 ②）。
##
## 守四件事：
##   1. 三个破坏原语（fracture / detach / fracture_pixels）之后，**母体**的质量仍按材质
##      密度算（= 剩余像素数 x 密度），摩擦/恢复系数**保持材质里配的值**；
##   2. 碎片同样正确（它们走 add_body 的兜底，本来就是对的 —— 这里防回归）；
##   3. **不传 Callable 的 rebuild 不能把摩擦/恢复清成 0**（"我不知道" != "它是 0"）；
##   4. 参照物**独立**：像素数用 shape.pixel_count() 数出来，密度/摩擦用配置值 ——
##      不拿引擎算出来的 mass/friction 自己跟自己比。
##
## ⚠️ 为什么值得一个闸门：这些量是**静默**错的。打一次洞，那块石头就变轻（质量=像素数）
##    变滑（摩擦 0），而画面、碰撞、测试都不会报错 —— 只有手感变了。
##    游戏层为此必须自己再调一次 refresh_mass()，把逐像素扫描 + 贪心分解 + 碰撞体重推
##    + 整张贴图重建再付一遍（768x100 实测 44 ms）。这条闸门就是"可以删掉那次调用"的依据。
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const Destruction := preload("res://src/core/destruction.gd")

const DENSITY := 2.5
const FRICTION := 0.9
const RESTITUTION := 0.4

var _pass := 0
var _fail := 0
func _c(n: String, ok: bool, d: String = "") -> void:
	if ok:
		_pass += 1
		print("  PASS  ", n, "  ", d)
	else:
		_fail += 1
		print("  FAIL  ", n, "  ", d)


func _world_with_body() -> Array:
	var w := PWorld.new()
	w.gravity = Vector2.ZERO
	w.set_material_density(1, DENSITY)
	w.set_material_friction(1, FRICTION)
	w.set_material_restitution(1, RESTITUTION)
	var b := PBody.new()
	b.position = Vector2(100, 100)
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, 40, 40), 1)
	w.add_body(b, [s])
	return [w, b]


func _pixels(b) -> int:
	var n := 0
	for s in b.shapes:
		n += s.pixel_count()
	return n


## 母体 + 碎片的材质属性都必须对（碎片走 add_body 兜底）。
func _check(label: String, b, frags: Array) -> void:
	var px := _pixels(b)
	var want := float(px) * DENSITY
	_c("%s：母体质量 = 剩余像素 x 密度" % label, absf(b.mass - want) < 0.01,
		"mass=%.2f，%d 像素 -> 期望 %.2f" % [b.mass, px, want])
	_c("%s：母体摩擦保持材质值" % label, absf(b.friction - FRICTION) < 1e-6,
		"friction=%.4f（材质 %.1f）" % [b.friction, FRICTION])
	_c("%s：母体恢复系数保持材质值" % label, absf(b.restitution - RESTITUTION) < 1e-6,
		"restitution=%.4f（材质 %.1f）" % [b.restitution, RESTITUTION])
	for f in frags:
		var fpx := _pixels(f)
		_c("%s：碎片质量 = 像素 x 密度" % label, absf(f.mass - float(fpx) * DENSITY) < 0.01,
			"mass=%.2f，%d 像素" % [f.mass, fpx])
		_c("%s：碎片摩擦保持材质值" % label, absf(f.friction - FRICTION) < 1e-6,
			"friction=%.4f" % f.friction)


func _initialize() -> void:
	print("=== 破坏之后的材质属性（表 ②）===")

	# ---- 0. 对照：没破坏过的刚体 ----
	var w0 := _world_with_body()
	var b0: PBody = w0[1]
	_c("对照：新刚体质量 = 1600 像素 x 2.5", absf(b0.mass - 4000.0) < 0.01, "mass=%.1f" % b0.mass)
	_c("对照：新刚体摩擦 = 0.9", absf(b0.friction - FRICTION) < 1e-6, "%.4f" % b0.friction)
	_c("对照：新刚体恢复 = 0.4", absf(b0.restitution - RESTITUTION) < 1e-6, "%.4f" % b0.restitution)

	# ---- 1. fracture（内部 10x10） ----
	var w1 := _world_with_body()
	var b1: PBody = w1[1]
	var frags1: Array = w1[0].fracture(b1, Destruction.Damage.rect(Vector2(20, 20), Vector2(5, 5)))
	print("  fracture：剩 %d 像素，碎片 %d 个" % [_pixels(b1), frags1.size()])
	_check("fracture", b1, frags1)

	# ---- 2. detach（内部 10x10） ----
	var w2 := _world_with_body()
	var b2: PBody = w2[1]
	var frags2: Array = w2[0].detach(b2, Destruction.Damage.rect(Vector2(20, 20), Vector2(5, 5)))
	print("  detach：剩 %d 像素，碎片 %d 个" % [_pixels(b2), frags2.size()])
	_check("detach", b2, frags2)
	# ⚠️ 这条我第一版写成了恒真（`x == x or true`）—— 项目里栽过"恒真断言"，
	#    所以这里**真的把碎片像素数加起来**：detach 的语义是"体素个数守恒"。
	var total_px := _pixels(b2)
	for f2 in frags2:
		total_px += _pixels(f2)
	_c("detach：体素守恒（母体 + 碎片 = 1600）", total_px == 1600,
		"母体 %d + 碎片 = %d" % [_pixels(b2), total_px])

	# ---- 3. fracture_pixels（内部 10x10 掩码） ----
	var w3 := _world_with_body()
	var b3: PBody = w3[1]
	var mask := {}
	for y in range(15, 25):
		for x in range(15, 25):
			mask[Vector2i(x, y)] = true
	var res: Dictionary = w3[0].fracture_pixels(b3, {b3.shapes[0]: mask})
	var frags3: Array = res.get("fragments", [])
	print("  fracture_pixels：删 %d，剩 %d 像素，碎片 %d 个" % [res["removed"], _pixels(b3), frags3.size()])
	_check("fracture_pixels", b3, frags3)

	# ---- 4. 不传 Callable 的 rebuild 不能把摩擦/恢复清成 0 ----
	var w4 := _world_with_body()
	var b4: PBody = w4[1]
	var before_f := b4.friction
	var before_r := b4.restitution
	b4.rebuild(b4.shapes)                      # 老式的"不带任何表"的调用（编辑器/ShapeOps 那条路）
	_c("不传 Callable：摩擦保持原值（不是 0）", absf(b4.friction - before_f) < 1e-9,
		"%.4f -> %.4f" % [before_f, b4.friction])
	_c("不传 Callable：恢复系数保持原值（不是 0）", absf(b4.restitution - before_r) < 1e-9,
		"%.4f -> %.4f" % [before_r, b4.restitution])

	print("---")
	if _fail == 0:
		print("全部通过：%d 项断言" % _pass)
	else:
		print("失败 %d / %d 项" % [_fail, _pass + _fail])
	quit(0 if _fail == 0 else 1)

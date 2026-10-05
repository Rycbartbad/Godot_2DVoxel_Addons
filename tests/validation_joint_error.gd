extends SceneTree
## 关节**约束误差**诊断的闸门（R3 要的"锚点误差 / 角差"）。
##
## ⚠️ 判据用**人为造出来的已知误差**：把刚体瞬移/转一个已知量，再读误差 ——
##    期望值是我自己给的（位移、转角），不是引擎算出来的数。这样"读数正确"才是可证的。
##
## 守四件事：
##   1. 完好时误差 ≈ 0（别拿噪声当误差）；
##   2. 瞬移后 anchor_error == 位移量（逐位）、转角后 angle_error == 转角（逐位）；
##   3. WELD 的 angle_error 必须**独立于 movement()**（后者恒 0，看不出焊接被拉歪）；
##   4. 滑轨的 lateral_error 只给"被锁住的那一行"，沿轴的分量留给 movement()。
##
## ⚠️ 全程**不 step**：误差是位姿的函数，stepping 会让约束把它拉回去（那就测不出来了）。

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

func _box(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _pair(w: PWorld) -> Array:
	var a := PBody.new()
	a.position = Vector2(100, 100)
	w.add_body(a, [_box(20, 20)])
	var b := PBody.new()
	b.position = Vector2(140, 100)
	w.add_body(b, [_box(20, 20)])
	return [a, b]

func _initialize() -> void:
	print("=== 关节约束误差诊断 ===")
	var w := PWorld.new()
	w.gravity = Vector2.ZERO
	var ab := _pair(w)
	var a: PBody = ab[0]
	var b: PBody = ab[1]

	# ---- 1. 焊接：完好时 ≈ 0 ----
	var weld = w.add_weld(a, b)
	_c("焊接创建后锚点误差 ≈ 0", weld.anchor_error_len() < 1e-6, "%.9f px" % weld.anchor_error_len())
	_c("焊接创建后角差 ≈ 0", absf(weld.angle_error()) < 1e-6, "%.9f rad" % weld.angle_error())
	_c("焊接的 movement() 恒为 0（所以角差必须单独取）", weld.movement() == 0.0)

	# ---- 2. 人为造已知误差：先瞬移，再转（两步各自有**自己算出来的**预期） ----
	#
	# ⚠️ 我第一版把两步一起做，然后期望"误差 == 位移"——**错了**：
	#    锚点是**刚体局部**坐标，转刚体会让锚点绕刚体原点划一段弧，那一段也要算进误差。
	#    实测 (0.836838, -6.784912)，正是 位移 + (局部锚点转过来的那一段) —— 见下面第二段。
	var shift := Vector2(3.0, -4.0)
	b.position += shift
	var err: Vector2 = weld.anchor_error()
	_c("瞬移后锚点误差 == 位移（逐位）", absf(err.x - 3.0) < 1e-6 and absf(err.y + 4.0) < 1e-6,
		"%s vs %s" % [str(err), str(shift)])
	var turn := 0.25
	b.rotation += turn
	# 期望值**自己算**：位移 + (局部锚点绕刚体原点转 turn 之后多出来的那一段)。
	# b.rotation 创建时是 0，所以世界系的那一段就是 la.rotated(turn) - la。
	var extra: Vector2 = weld.local_anchor_b.rotated(turn) - weld.local_anchor_b
	var want := shift + extra
	err = weld.anchor_error()
	# ⚠️ 容差 1e-4 而不是 1e-6：锚点走的是 `body.to_world()`，而 Vector2 是 **float32**
	#    （本项目的老坑：GDScript 标量是 float64，Vector2/Rect2 不是）。
	#    量级 150 的 float32 分辨率约 1.2e-5 —— 实测差 2e-6，是两种算法顺序的 ULP 差。
	_c("转角后锚点误差 == 位移 + 锚点划出的弧（自己算的预期）",
		absf(err.x - want.x) < 1e-4 and absf(err.y - want.y) < 1e-4, "%s vs %s" % [str(err), str(want)])
	_c("转角后角差 == 转角", absf(weld.angle_error() - turn) < 1e-9, "%.9f vs %.9f" % [weld.angle_error(), turn])
	_c("焊接的 movement() 仍然是 0（角差没被它盖住）", weld.movement() == 0.0)

	# ---- 3. 滑轨：沿轴归 movement()，横向归 lateral_error() ----
	var w2 := PWorld.new()
	w2.gravity = Vector2.ZERO
	var ab2 := _pair(w2)
	var a2: PBody = ab2[0]
	var b2: PBody = ab2[1]
	var slide = w2.add_slider(a2, b2)      # 默认轴 = Vector2.RIGHT
	_c("滑轨创建后横向漂移 ≈ 0", slide.lateral_error().length() < 1e-6)
	var move := Vector2(5.0, 2.0)
	b2.position += move
	_c("沿轴分量归 movement()", absf(slide.movement() - 5.0) < 1e-6, "%.6f" % slide.movement())
	var lat: Vector2 = slide.lateral_error()
	_c("横向分量归 lateral_error()（只给被锁住那一行）",
		absf(lat.x) < 1e-6 and absf(lat.y - 2.0) < 1e-6, "%s" % str(lat))
	_c("两者合起来 == 总位移", ((slide.world_axis() * slide.movement()) + lat).is_equal_approx(move))

	# ---- 4. 静态端（body == null = 静态世界） ----
	var w3 := PWorld.new()
	w3.gravity = Vector2.ZERO
	var ab3 := _pair(w3)
	var b3: PBody = ab3[1]
	var hinge = w3.add_hinge(null, b3, Vector2(120, 100))
	_c("静态端创建后锚点误差 ≈ 0", hinge.anchor_error_len() < 1e-6)
	b3.position += Vector2(0.0, 7.0)
	_c("静态端瞬移后锚点误差 == 位移", absf(hinge.anchor_error().y - 7.0) < 1e-6,
		"%s" % str(hinge.anchor_error()))
	_c("铰链：angle_error 与 movement() 同式（别让两份实现漂开）",
		absf(hinge.angle_error() - hinge.movement()) < 1e-12)

	print("---")
	if _fail == 0:
		print("全部通过：%d 项断言" % _pass)
	else:
		print("失败 %d / %d 项" % [_fail, _pass + _fail])
	quit(0 if _fail == 0 else 1)

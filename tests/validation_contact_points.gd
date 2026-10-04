extends SceneTree
## 接触点导出接口的闸门（op 35 / PWorld.contact_points）。
##
## ⚠️⚠️ 守的是什么：一次物理更新里，整个接触面可以同时存在多个接触点
##    （60 Hz 是**更新时间**，不是接触数量限制；面-面接触通常 2 个）。
##    旧接口只取**第一个流形的第一个点**作位置，却返回整对的**总冲量**
##    —— 一个点背着整个面的冲量。照那个点打洞，宽面撞击就会集中成一次尖刺。
##
## 这里钉四件事：
##   1. 平放方块撞击给出 **2 个点**（不是 1 个）
##   2. 两点位置**不同**，且张成的跨度 ≈ 方块宽度（即"接触段的两端"，不是同一个代表点）
##   3. 两点冲量都 > 0 且**相等**（对称撞击）
##   4. dist < 0 —— 真穿透。⚠️ 推测接触 dist > 0 时**也有冲量**（那是在阻止接近），
##      所以伤害判据不能只看冲量，否则擦身而过也会打洞。
##
## ⚠️ "Σ各点冲量 = 整对总冲量"这一条由 tests/diag_contact_points4.gd 实测钉住
##    （1280.0001 + 1280.0001 = 2560.0002，比值 1.000）—— 本闸门只查公开接口能拿到的量。

const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

var passed := 0
var failed := 0

func _assert(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("  [失败] " + msg)

func _box(w: int, h: int, mat: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), mat)
	return s

func _initialize() -> void:
	print("=== 接触点导出接口 ===")
	var w := PWorld.new()
	w.gravity = Vector2(0, 600)
	var ground := PBody.new()
	ground.position = Vector2(0, 100)
	ground.make_static()
	w.add_body(ground, [_box(200, 8, 1)], Callable(), true)
	var box := PBody.new()
	box.position = Vector2(50, 84)
	w.add_body(box, [_box(32, 8, 2)], Callable(), true)
	w._rp_ensure()
	var best := 0
	for i in 90:
		w.step(1.0 / 60.0)
		best = maxi(best, w.contact_pair_count())
	print("  接触对计数最大 = %d" % best)
	_assert(best >= 1, "平放方块落在地面上却没有接触对（计数 %d）" % best)
	if best <= 0:
		quit(1)
		return
	var pts: Array = w.contact_points(0)
	print("  点数 = %d" % pts.size())
	_assert(pts.size() == 2, "面-面接触应当是 2 个点，实际 %d" % pts.size())
	if pts.size() != 2:
		quit(1)
		return
	var p0: Dictionary = pts[0]
	var p1: Dictionary = pts[1]
	var d: float = (p1["position"] - p0["position"]).length()
	print("  两点距离 = %.3f（方块宽 32）" % d)
	_assert(d > 1.0, "两个点位置几乎相同（距离 %.3f）—— 又退回一个代表点了" % d)
	_assert(absf(d - 32.0) < 1.0, "两点跨度应 ≈ 方块宽度 32，实际 %.3f" % d)
	print("  冲量 = %.4f / %.4f，dist = %.4f / %.4f" % [
		p0["impulse"], p1["impulse"], p0["dist"], p1["dist"]])
	_assert(p0["impulse"] > 0.0 and p1["impulse"] > 0.0, "有接触点冲量为 0")
	_assert(absf(p0["impulse"] - p1["impulse"]) < 0.01 * maxf(p0["impulse"], 1e-9),
		"对称撞击下两点冲量应当相等：%.4f vs %.4f" % [p0["impulse"], p1["impulse"]])
	_assert(p0["dist"] < 0.0 and p1["dist"] < 0.0, "撞击帧的 dist 应为负（真穿透）")
	print("---")
	if failed == 0:
		print("全部通过：%d 项断言" % passed)
	else:
		print("失败 %d / %d 项" % [failed, passed + failed])
	quit(0 if failed == 0 else 1)

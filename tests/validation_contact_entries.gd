extends SceneTree
## 共享预算的损伤入口分配（Destruction.contact_entries）闸门。
##
## 守四件事：
##   1. 份额之和 = 1（各点冲量之和 = 总冲量，实测比值 1.000）
##   2. **面积守恒**：Σ pi*r_i^2 ~= pi*base^2（半径正比于 sqrt(份额)）—— 预算不被重复领取
##   3. dist > 0（推测接触）-> penetrating = false —— 擦身而过不打洞
##   4. 份额太小的入口被丢掉（避免一串微小入口）
const Destruction := preload("res://src/core/destruction.gd")

var passed := 0
var failed := 0

func _assert(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("  [失败] " + msg)

func _initialize() -> void:
	print("=== 共享预算的损伤入口 ===")
	var pts := [
		{"position": Vector2(50, 100), "dist": -0.049, "impulse": 1280.0001},
		{"position": Vector2(82, 100), "dist": -0.049, "impulse": 1280.0001},
	]
	var base := 8.0
	var e: Array = Destruction.contact_entries(pts, 2560.0002, base)
	print("  入口数 = %d" % e.size())
	_assert(e.size() == 2, "应当两个入口，实际 %d" % e.size())
	if e.size() != 2:
		quit(1)
		return
	var ss := 0.0
	var aa := 0.0
	for x in e:
		ss += x["share"]
		aa += PI * x["radius"] * x["radius"]
		print("  point=%s share=%.4f radius=%.4f penetrating=%s" % [
			str(x["point"]), x["share"], x["radius"], str(x["penetrating"])])
	var base_area := PI * base * base
	print("  份额之和 = %.6f；Σ面积 = %.4f，单点面积 = %.4f（比值 %.4f）" % [
		ss, aa, base_area, aa / base_area])
	_assert(absf(ss - 1.0) < 1e-6, "份额之和应为 1，实际 %.6f" % ss)
	_assert(absf(aa - base_area) < 1e-4 * base_area,
		"面积不守恒（比值 %.4f）—— 预算被重复领取" % (aa / base_area))
	_assert(e[0]["penetrating"] and e[1]["penetrating"], "dist < 0 应当是 penetrating")
	var spec := [{"position": Vector2(0, 0), "dist": 0.5, "impulse": 100.0}]
	var e2: Array = Destruction.contact_entries(spec, 100.0, base)
	_assert(e2.size() == 1 and not e2[0]["penetrating"], "推测接触不该被判为 penetrating")
	var tiny := [
		{"position": Vector2(0, 0), "dist": -0.1, "impulse": 99.0},
		{"position": Vector2(1, 0), "dist": -0.1, "impulse": 1.0},
	]
	var e3: Array = Destruction.contact_entries(tiny, 100.0, base)
	_assert(e3.size() == 1, "份额 0.01 的入口应被丢掉，实际留下 %d 个" % e3.size())
	print("---")
	if failed == 0:
		print("全部通过：%d 项断言" % passed)
	else:
		print("失败 %d / %d 项" % [failed, passed + failed])
	quit(0 if failed == 0 else 1)

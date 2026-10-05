extends SceneTree
## 抓取时的**子步代价上限**闸门。
##
## ⚠️⚠️ 背景：子步是**全局**的 —— 每个子步都要把整个世界步进一遍。而子步数按
##    "最快清醒刚体每帧位移 / ccd_max_motion(2.0)"算，**与接触无关** ->
##    抓着东西空挥也顶满：1000 矩形时一次快速拖动 = 25 子步 x 整个世界的代价。
##
##    修法是"抓取时按世界大小压一遍子步数"：PWorld.grab_substep_cap()，
##    即 预算(us) / (总矩形数 x 每矩形每子步的实测代价 CCD_RECT_COST_US)。
##    ⚠️ **只在抓取时**生效 —— 不抓时完全走原来的行为，所以 8 条基准逐位不变。
##
## ⚠️⚠️ 这个文件里曾经**自己抄了一遍公式**（budget / total_rects，按 1 us/矩形 标定）。
##    标定更正成 4.4 us/矩形 之后，抄的那份就比引擎松了 4.4 倍 —— 而这里的断言是
##    "子步 <= 上限"，上限算大了就**永远通过**：闸门会静默失效。现在改调
##    @@w.grab_substep_cap(total)@@（唯一真源），并额外钉一条"实测代价别超预算"。
##
## 这里钉四件事：
##   1. 抓取 + 高速时子步数被压到上限附近，且帧时间**在预算内**
##   2. **松手之后上限不再生效**（否则就是把基准走的那条路也改了）
##   3. 上限是确定性的：同一状态反复调用给出同一个值（不看挂钟）
##      —— 上一版用挂钟做预算，sleep_frag 从 -35.696264844083 变成 -35.400524684771
##      且两次运行不一致，已整段撤回。
##   4. 上限是按**实测代价**换算的（本场景 1001 矩形 -> 1 子步），
##      所以最坏帧时间必须落在 ccd_grab_substep_cost_budget_us 附近 ——
##      标定常数被改小（上限说谎）时这条会先响。

const AddonWorld := preload("res://src/nodes/pixel_world.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const PBody := preload("res://src/physics/pbody.gd")

var passed := 0
var failed := 0

func _assert(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		if failed <= 8:
			print("  [失败] " + msg)

func _initialize() -> void:
	print("=== 抓取子步的代价上限 ===")
	var pw = AddonWorld.new()
	get_root().add_child(pw)
	await process_frame
	var w = pw.world
	var dt := 1.0 / 60.0
	var big := PBody.new()
	var s := PixelShape.new()
	for j in 1000:
		s.fill_rect(Rect2i(0, j * 2, 200, 1), 1)
	w.add_body(big, [s], Callable(), true)
	var faller := PBody.new()
	faller.position = Vector2(-5000, -500)
	var s2 := PixelShape.new()
	s2.fill_rect(Rect2i(0, 0, 8, 8), 1)
	w.add_body(faller, [s2], Callable(), true)
	var total := 0
	for b in w.bodies:
		total += b.rects.size()
	# ⚠️ 用引擎自己的换算（唯一真源），别再在这里抄一遍公式
	var cap: int = w.grab_substep_cap(total)
	var budget_ms := float(w.ccd_grab_substep_cost_budget_us) / 1000.0
	print("  总矩形 %d -> 抓取时上限 %d 子步（每步预算 %.1f ms）" % [total, cap, budget_ms])
	# ① 抓取 + 高速：必须被压住
	w.grab(big, Vector2(100, 0))
	var worst := 0.0
	var max_seen := 0
	for i in 12:
		big.linear_velocity = Vector2(0, -3000)
		var t0 := Time.get_ticks_usec()
		w.step(dt)
		worst = maxf(worst, (Time.get_ticks_usec() - t0) / 1000.0)
		max_seen = maxi(max_seen, w.last_substeps)
	print("  抓取 + 高速：实际子步最大 %d，最坏帧 %.2f ms" % [max_seen, worst])
	_assert(max_seen <= cap + 1, "抓取时子步没被压住：%d > 上限 %d" % [max_seen, cap])
	# ⚠️ 上限是"每步预算"，所以最坏帧时间必须落在预算附近（给 1.5 倍余量：
	#    子步数取整、每子步的固定开销、以及 CCD_RECT_COST_US 本身的场景散布）。
	_assert(worst <= budget_ms * 1.5,
		"抓取时一帧超出预算：%.2f ms > %.2f ms（标定常数偏小 = 上限说谎？）" % [worst, budget_ms * 1.5])
	_assert(worst < 20.0, "抓取时帧时间没被压住：%.2f ms" % worst)
	# ② 松手后上限不再生效（这正是基准走的路）
	w.release_grab()
	big.linear_velocity = Vector2(0, -3000)
	w.step(dt)
	var after: int = w.last_substeps
	print("  松手后同速：子步 %d（上限 %d）" % [after, cap])
	_assert(after > cap, "松手后上限仍生效（%d <= %d）—— 那会把基准走的路也改掉" % [after, cap])
	# ③ 确定性：同一状态重复给出同一个值
	big.linear_velocity = Vector2(0, -3000)
	# ⚠️ 必须显式标注类型：_compute_substeps 的返回在静态分析里没有确定类型，
	#    用 := 会报 "Cannot infer the type of v1"（GDScript 的经典坑）。
	var v1: int = w._compute_substeps(dt)
	big.linear_velocity = Vector2(0, -3000)
	var v2: int = w._compute_substeps(dt)
	_assert(v1 == v2, "同一状态两次算出不同子步数：%d vs %d" % [v1, v2])
	print("  确定性：同一状态两次 -> %d / %d" % [v1, v2])
	print("---")
	if failed == 0:
		print("全部通过：%d 项断言" % passed)
	else:
		print("失败 %d / %d 项" % [failed, passed + failed])
	quit(0 if failed == 0 else 1)
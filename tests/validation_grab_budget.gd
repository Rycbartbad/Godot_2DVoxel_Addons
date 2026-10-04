extends SceneTree
## 抓取时的**子步代价上限**闸门。
##
## ⚠️⚠️ 背景：子步是**全局**的 —— 每个子步都要把整个世界步进一遍。实测每子步成本
##    ≈ 1 us/矩形。而子步数按"最快清醒刚体每帧位移 / ccd_max_motion(2.0)"算，
##    **与接触无关** -> 抓着东西空挥也顶满：1000 矩形时一次快速拖动 = 25 子步 x 1 ms
##    = 25 ms/帧（用户报的"拖动掉到 8 帧"，他的场景更重 -> 125 ms）。
##
##    修法是"抓取时按世界大小压一遍子步数"（ccd_grab_substep_cost_budget_us / 总矩形数）。
##    ⚠️ **只在抓取时**生效 —— 不抓时完全走原来的行为，所以 8 条基准逐位不变。
##
## 这里钉三件事：
##   1. 抓取 + 高速时子步数被压到上限附近，且帧时间有界
##   2. **松手之后上限不再生效**（否则就是把基准走的那条路也改了）
##   3. 上限是确定性的：同一状态反复调用给出同一个值（不看挂钟）
##      —— 上一版用挂钟做预算，sleep_frag 从 -35.696264844083 变成 -35.400524684771
##      且两次运行不一致，已整段撤回。

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
	var cap: int = maxi(1, w.ccd_grab_substep_cost_budget_us / total)
	print("  总矩形 %d -> 抓取时上限 %d 子步" % [total, cap])
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

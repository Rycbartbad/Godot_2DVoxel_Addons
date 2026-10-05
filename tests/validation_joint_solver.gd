extends SceneTree
## **关节求解精度**闸门（R3 的原生旋钮：软度 / 迭代次数 / warmstart）。
##
## 守六件事：
##   1. 软度**真的生效**：频率调低 -> 锚点漂移变大（默认 0.000 px -> 2 Hz 时 22 px 量级）；
##   2. 软度**调得回去**（frequency <= 0 = 回 Rapier 默认，漂移逐位回到 0）；
##   3. 迭代次数**真的生效**且方向对（1 次误差远大于默认，8 次略小于默认）；
##   4. Rapier 的默认迭代次数就是 **4**（显式设 4 与"不设"结果逐位相同）；
##   5. warmstart 开关在**已收敛**的场景里不改变结果（实测如此，写在这里当行为契约：
##      Rapier 0.36 里它对冲量关节没有可观测影响 —— 留着它是排查用的开关）；
##   6. **不设就不推**（默认三个旋钮都不推，所以 8 条逐位基准不受影响）。
##
## ⚠️ 判据是**外部可观测量**：PJoint.anchor_error_len()（锚点漂移，px）与末端位置 ——
##    不读引擎内部标志当预期值（唯一的例外是第 6 条的"不推"契约，那条本来就是内部契约）。
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

const DT := 1.0 / 60.0

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


## 一个 40x40 方块焊在世界锚点上，重力往下拉 120 步 -> 锚点漂移（px）。
func _hang_drift(freq: float) -> float:
	var w := PWorld.new()
	w.gravity = Vector2(0, 500)
	var b := PBody.new()
	w.add_body(b, [_box(40, 40)])
	var j = w.add_weld(null, b, Vector2(20, 0))
	if freq >= 0.0:
		j.set_solver_softness(freq)
	for i in 120:
		w.step(DT)
	return j.anchor_error_len()


## 12 节焊链一端焊在世界上，跑 600 步**静定之后**再量：返回 [误差和, 末端 y]。
func _chain_settled(iters: int, warm: int) -> Array:
	var w := PWorld.new()
	w.gravity = Vector2(0, 800)
	if iters > 0:
		w.rp_joint_solver_iterations = iters
	if warm >= 0:
		w.rp_warmstart_joints = warm
	var prev = null
	var joints: Array = []
	for i in 12:
		var b := PBody.new()
		b.position = Vector2(i * 20, 0)
		w.add_body(b, [_box(20, 20)])
		joints.append(w.add_weld(null, b, Vector2(10, 0)) if prev == null else w.add_weld(prev, b, Vector2(i * 20, 10)))
		prev = b
	for s in 600:
		w.step(DT)
	var err_sum := 0.0
	for j in joints:
		err_sum += j.anchor_error_len()
	var last = w.bodies[w.bodies.size() - 1]
	return [err_sum, last.position.y]


func _initialize() -> void:
	print("=== 关节求解精度（R3 原生旋钮）===")

	# ---- 1/2. 软度 ----
	var d_default := _hang_drift(-1.0)
	var d_soft := _hang_drift(2.0)
	var d_mid := _hang_drift(8.0)
	var d_reset := _hang_drift(0.0)
	print("  软度：默认 %.6f px | 2 Hz %.6f | 8 Hz %.6f | 回默认 %.6f" % [d_default, d_soft, d_mid, d_reset])
	_c("默认焊接几乎不漂（< 0.01 px）", d_default < 0.01, "%.6f px" % d_default)
	_c("软度生效：2 Hz 漂移远大于默认", d_soft > 5.0, "%.3f px" % d_soft)
	_c("软度单调：8 Hz 比 2 Hz 硬", d_mid < d_soft, "%.3f < %.3f" % [d_mid, d_soft])
	_c("软度调得回去：frequency <= 0 -> 回 Rapier 默认", absf(d_reset - d_default) < 1e-9,
		"%.6f vs 默认 %.6f" % [d_reset, d_default])

	# ---- 3/4/5. 迭代次数 / warmstart ----
	var base := _chain_settled(0, -1)
	var one := _chain_settled(1, -1)
	var eight := _chain_settled(8, -1)
	var four := _chain_settled(4, -1)
	var nowarm := _chain_settled(0, 0)
	print("  焊链 600 步：默认 %.4f px（末端 y=%.3f）| 迭代 1 %.4f | 迭代 8 %.4f" % [
		base[0], base[1], one[0], eight[0]])
	_c("迭代 1 次：约束误差显著变大", one[0] > base[0] * 2.0, "%.4f vs %.4f" % [one[0], base[0]])
	_c("迭代 8 次：误差不大于默认", eight[0] <= base[0], "%.4f <= %.4f" % [eight[0], base[0]])
	_c("Rapier 默认迭代次数就是 4（显式设 4 与不设逐位相同）",
		absf(four[0] - base[0]) < 1e-12 and absf(four[1] - base[1]) < 1e-12,
		"%.4f / y=%.3f" % [four[0], four[1]])
	_c("warmstart 关掉：已收敛场景结果不变（行为契约，见文件头）",
		absf(nowarm[0] - base[0]) < 1e-12 and absf(nowarm[1] - base[1]) < 1e-12,
		"%.4f / y=%.3f" % [nowarm[0], nowarm[1]])

	# ---- 6. 不设就不推（默认契约） ----
	var w6 := PWorld.new()
	_c("默认：三个旋钮都是'不推'的值",
		w6.rp_joint_solver_iterations == 0 and w6.rp_warmstart_joints < 0 and w6.rp_warmstart_coefficient < 0.0,
		"iters=%d warm=%d coeff=%.1f" % [w6.rp_joint_solver_iterations, w6.rp_warmstart_joints, w6.rp_warmstart_coefficient])
	var b6 := PBody.new()
	w6.add_body(b6, [_box(8, 8)])
	b6.linear_velocity = Vector2(100, 0)
	w6.step(DT)
	_c("默认：一个子步都没推过 op 41", w6._rp_joint_solver_pushed == false)
	_c("新关节的软度镜像 = 未推过（-1）", PJointSoftnessUnpushed(w6))

	# ---- 7. 它**不是关节专属**旋钮（这条是实测出来的，不是假设） ----
	#
	# ⚠️ 我原本以为"关节求解迭代次数"只影响关节 —— 实测打脸：连**没有任何关节**的自由落体
	#    结果都会变（223.6367 vs 225.3281）。Rapier 0.36 的 num_solver_iterations 是
	#    **整个求解**（含接触与积分）的迭代次数，所以调它等于调全局精度。
	#    这条断言把事实钉住：文档里也必须这么写。
	var y_a := _freefall_y()
	var y_b := _freefall_y(1)
	_c("迭代次数是**全局**求解参数：无关节的落体结果也会变（实测）", absf(y_a - y_b) > 1e-9,
		"%.6f vs %.6f" % [y_a, y_b])

	print("---")
	if _fail == 0:
		print("全部通过：%d 项断言" % _pass)
	else:
		print("失败 %d / %d 项" % [_fail, _pass + _fail])
	quit(0 if _fail == 0 else 1)


## 无关节落体 60 步后的 y（可选地设迭代次数）。
func _freefall_y(iters: int = 0) -> float:
	var w := PWorld.new()
	w.gravity = Vector2(0, 500)
	if iters > 0:
		w.rp_joint_solver_iterations = iters
	var b := PBody.new()
	w.add_body(b, [_box(8, 8)])
	for i in 60:
		w.step(DT)
	return b.position.y


## 新关节的软度镜像应当是"未推过"（-1）。
func PJointSoftnessUnpushed(w) -> bool:
	var b := PBody.new()
	w.add_body(b, [_box(8, 8)])
	var b2 := PBody.new()
	b2.position = Vector2(50, 0)
	w.add_body(b2, [_box(8, 8)])
	var j = w.add_weld(b, b2)
	return j._rp_soft_freq < 0.0

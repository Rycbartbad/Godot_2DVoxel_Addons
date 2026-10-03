extends SceneTree
## 回归：抓取一个方块时，其它方块**不得掉穿地面**。
##
## 曾经的 bug（求解器移植引入，现已不可能复现）：
##   · 宽相按"是否走 native"跳过对象装配 -> manifolds 置空
##   · 求解的判断却是"走 native" **且 grabs.is_empty()** -> 有抓取时退回对象路径
##   两处判断不一致，于是求解器拿到**空流形数组**：所有接触约束消失。
##   被抓住的方块还有抓取约束吊着，其余的一起自由落体穿地而过。
##
## ⚠️ 现在只有 native 一条路（对象路径已删除），所以这个 bug 在结构上不可能再出现。
##    保留这个测试是因为它测的**行为**仍然重要：抓着东西时其余物体不得穿地。
##
## 这个测试用"先复现再验证"的方式钉住它：把判断改回旧写法（--bug）应当 FAIL。

const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const Grab := preload("res://src/physics/grab.gd")

func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

func _run(with_grab: bool) -> Dictionary:
	var w := PWorld.new()
	# ⚠️ 必须关掉休眠才能复现：bug 版本里 _wake_pass 用的是打包数据、工作正常，
	#    睡着的方块不会自己醒 —— 于是"看着没事"。真实场景里方块刚被扰动过、
	#    是**醒着**的，那一瞬间接触约束丢失就会穿地。
	w.sleeping_enabled = false
	var g := PBody.new()
	g.position = Vector2(-300.0, 0.0)
	g.make_static()
	w.add_body(g, [_block(600, 40)])
	var boxes: Array = []
	for i in 6:
		var b := PBody.new()
		b.position = Vector2(-60.0 + float(i) * 24.0, -16.0)
		w.add_body(b, [_block(16, 16)])
		boxes.append(b)
	for i in 120:                        # 先落稳
		w.step(1.0 / 60.0)
	var rest: Array = []
	for b in boxes:
		rest.append(b.position.y)
	var gr: Grab = null
	if with_grab:
		gr = Grab.new()
		gr.body = boxes[2]
		gr.local_anchor = Vector2.ZERO
		w.grabs.append(gr)
	for i in 180:                        # 把中间那个抬到地面上方并吊住
		if gr != null:
			gr.target = Vector2(-12.0, -160.0)
		w.step(1.0 / 60.0)
	var worst := 1.0e18
	var sunk := 0
	for i in boxes.size():
		if i == 2:
			continue
		worst = minf(worst, (boxes[i] as PBody).position.y - float(rest[i]))
		if (boxes[i] as PBody).position.y - float(rest[i]) > 4.0:
			sunk += 1
	return {"sunk": sunk, "worst": worst, "dragged_y": (boxes[2] as PBody).position.y}

func _initialize() -> void:
	var bug := OS.get_cmdline_user_args().has("--bug")
	var ctl := _run(false)
	var grb := _run(true)
	print("对照（无抓取）: 下沉 %d 个，最大位移 %.4f" % [ctl["sunk"], ctl["worst"]])
	print("抓取中        : 下沉 %d 个，最大位移 %.4f，被拖方块 y=%.4f" % [
		grb["sunk"], grb["worst"], grb["dragged_y"]])
	var ok: bool = ctl["sunk"] == 0 and grb["sunk"] == 0
	if bug:
		# 复现模式：期望**失败**（说明测试确实能抓到旧 bug）
		print("=== 复现模式（期望 FAIL）: %s ===" % ("FAIL（符合预期，旧 bug 被复现）" if not ok else "PASS（没能复现，测试无效！）"))
	else:
		print("=== %s ===" % ("PASS" if ok else "FAIL"))
	quit(0)

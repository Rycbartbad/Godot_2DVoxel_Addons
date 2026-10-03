extends SceneTree
## 材质摩擦系数 / 碰撞恢复系数：从材质表一路走到 Rapier，并用**可观测的物理后果**验收。
##
## ⚠️ 判据选的是"滑多远"和"弹多高"，不是"系数设进去了" —— 后者只能证明我们
##    往命令流里写了字节，证明不了 Rapier 真的用了它。
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
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

## ⚠️ 材质是**逐像素**存的：fill_rect 的第二个参数就是材质 id。
func _rect(w: int, h: int, mat := 1) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), mat)
	return s


## 一块箱子以 v0 在地面上滑：摩擦越大滑得越近。
func _slide(friction: float) -> float:
	var world := PWorld.new()
	world.gravity = Vector2(0, 600)
	world.set_material_friction(1, friction)
	var ground := PBody.new()
	ground.position = Vector2(0, 200)
	ground.make_static()
	world.add_body(ground, [_rect(1200, 40, 2)])
	var box := PBody.new()
	box.position = Vector2(100, 160)
	world.add_body(box, [_rect(16, 16)])
	box.linear_velocity = Vector2(300, 0)
	for i in 240:
		world.step(1.0 / 60.0)
	return box.position.x - 100.0


## 一个球从高处落到地面：恢复系数越大弹得越高（取落地后的最大回弹高度）。
func _bounce(restitution: float, ground_restitution := 0.0) -> float:
	var world := PWorld.new()
	world.gravity = Vector2(0, 600)
	world.set_material_restitution(1, restitution)
	world.set_material_restitution(2, ground_restitution)
	var ground := PBody.new()
	ground.position = Vector2(0, 200)
	ground.make_static()
	world.add_body(ground, [_rect(600, 40, 2)])
	var ball := PBody.new()
	ball.position = Vector2(100, 100)
	world.add_body(ball, [_rect(12, 12)])
	# ⚠️ 判据是"**弹起来之后**的最大高度"，不是"越过某个 y 之后的最大高度" ——
	#    第一版写成后者，把**下落过程**也算进去了：两种情况都量到 19.3 px（其实是
	#    从 y=180 落到 188 的那段），看着像"恢复系数没生效"。
	var bounced := false
	var peak := 0.0
	for i in 300:
		world.step(1.0 / 60.0)
		if not bounced and ball.linear_velocity.y < -1.0 and ball.position.y > 170.0:
			bounced = true                   # 速度朝上 = 真的弹起来了
		if bounced:
			peak = maxf(peak, 200.0 - ball.position.y)
	return peak


func _initialize() -> void:
	print("=== 材质：摩擦系数 ===")
	var far := _slide(0.0)
	var near := _slide(0.9)
	# 阈值 150：摩擦 0 也会被线阻尼（0.35/s）拖慢，滑不到无限远。
	_c("摩擦 0 滑得远", far > 150.0, "滑了 %.1f px" % far)
	_c("摩擦 0.9 滑得近", near < far * 0.6, "滑了 %.1f px（无摩擦是 %.1f）" % [near, far])

	print("=== 材质：碰撞恢复系数 ===")
	var dead := _bounce(0.0)
	var bouncy := _bounce(0.9)
	_c("恢复 0 基本不弹", dead < 3.0, "回弹 %.1f px" % dead)
	# ⚠️ Rapier 的恢复系数是**两个碰撞体按 CoefficientCombineRule 合成**的（默认取平均）：
	#    球 0.9 + 地面 0（默认）-> 接触处 0.45 -> 回弹速度 45%，高度约 20%
	#    （落 88 px -> 弹 ~19 px）。这不是 bug，是合成规则 —— 想让球真的弹起来，
	#    **地面也要给恢复系数**，下面那条对照就是钉这个的。
	_c("恢复 0.9 弹得起来", bouncy > dead + 10.0, "回弹 %.1f px（不弹是 %.1f）" % [bouncy, dead])
	var both := _bounce(0.9, 0.9)
	_c("两边都是 0.9 才弹得高（合成规则取平均）", both > bouncy * 2.0,
		"回弹 %.1f px（只有球是 0.9 时 %.1f）" % [both, bouncy])

	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
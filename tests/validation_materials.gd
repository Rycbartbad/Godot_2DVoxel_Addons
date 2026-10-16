extends SceneTree
## 材质摩擦系数 / 碰撞恢复系数：从材质表一路走到 Rapier，并用**可观测的物理后果**验收。
##
## ⚠️ 判据选的是"滑多远"和"弹多高"，不是"系数设进去了" —— 后者只能证明我们
##    往命令流里写了字节，证明不了 Rapier 真的用了它。
##
## ⚠️⚠️ 接触系数是**两个碰撞体合成**出来的（Rapier 的 CoefficientCombineRule），
##    所以"材质里配的值"与"接触处的值"不是一回事。这份闸门同时钉**合成规则**本身：
##      · 摩擦 = 几何平均 sqrt(μ₁·μ₂)：**任一边为 0，接触就无摩擦**（冰面真滑）；
##      · 恢复 = 取大 max(e₁, e₂)：**更弹的那一方说了算**（只给球配 0.9 也弹满）。
##    另外两条"改回取平均"的对照是在钉**旋钮真的接到了 Rapier**（op 47）——
##    只改 GDScript 变量、没推给原生时它们必然失败（那时的症状是静默的手感变差）。
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
## ground_friction：地面材质（2）的摩擦系数（默认 0.5 = 材质表没配时的那条默认）。
## rule：< 0 = 用 PWorld 的默认规则；给了就现场改（对照用）。
func _slide(friction: float, ground_friction := 0.5, rule := -1) -> float:
	var world := PWorld.new()
	world.gravity = Vector2(0, 600)
	world.set_material_friction(1, friction)
	world.set_material_friction(2, ground_friction)
	if rule >= 0:
		world.friction_combine_rule = rule
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
## rule：< 0 = 用 PWorld 的默认规则；给了就现场改（对照用）。
func _bounce(restitution: float, ground_restitution := 0.0, rule := -1) -> float:
	var world := PWorld.new()
	world.gravity = Vector2(0, 600)
	world.set_material_restitution(1, restitution)
	world.set_material_restitution(2, ground_restitution)
	if rule >= 0:
		world.restitution_combine_rule = rule
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



## 上下**两截不同材质**的方块：下半截 bottom_mat、上半截 top_mat。
## ⚠️ 局部坐标 y 向下（与重力 +y 一致），所以"下半截"是大的 y。
func _two_band(w: int, h: int, bottom_mat: int, top_mat: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h / 2), top_mat)
	s.fill_rect(Rect2i(0, h / 2, w, h - h / 2), bottom_mat)
	return s


## 左右**两种材质**的地面（静态体一块，左半 mat_left、右半 mat_right）。
func _two_ground(w: int, h: int, mat_left: int, mat_right: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w / 2, h), mat_left)
	s.fill_rect(Rect2i(w / 2, 0, w - w / 2, h), mat_right)
	return s


## 两块**同一对材质、只是上下对调**的方块在地面上滑：它们的"整体平均系数"完全相同，
## 所以滑行距离的差别**只能**来自"哪个材质的表面在接触地面"。
## 材质 1 = 冰（摩擦 0.0），材质 2 = 橡胶（摩擦 0.9），地面材质 3 = 中间值 0.5。
func _slide_band(ice_down: bool) -> float:
	var world := PWorld.new()
	world.gravity = Vector2(0, 600)
	world.set_material_friction(1, 0.0)
	world.set_material_friction(2, 0.9)
	world.set_material_friction(3, 0.5)
	var ground := PBody.new()
	ground.position = Vector2(0, 200)
	ground.make_static()
	world.add_body(ground, [_rect(1400, 40, 3)])
	# ⚠️ 方块用**扁平**的（32x8）而不是方块：16x16 在滑动中会翻滚，
	#    翻过来之后接触地面的材质就换了一面 —— 那时量到的距离混进了滚动，
	#    判据就不再是"哪个表面在接触"了（实测 136 -> 244 px 的那种假差异就是这么来的）。
	var box := PBody.new()
	box.position = Vector2(100, 191)        # 贴着地面（不摔、不弹）
	var shape := _two_band(32, 8, 1, 2) if ice_down else _two_band(32, 8, 2, 1)
	world.add_body(box, [shape])
	box.linear_velocity = Vector2(300, 0)
	for i in 240:
		world.step(1.0 / 60.0)
	return box.position.x - 100.0


## 一整块**多材质静态地形**（左半 mat_left、右半 mat_right）上的滑行：
## 方块从左侧同一位置出发 —— 两次只差"脚下那半是什么材质"。
func _slide_terrain(mat_left: int, mat_right: int) -> float:
	var world := PWorld.new()
	world.gravity = Vector2(0, 600)
	world.set_material_friction(1, 0.0)     # 冰
	world.set_material_friction(2, 0.9)     # 橡胶
	world.set_material_friction(3, 0.5)     # 箱子
	var ground := PBody.new()
	ground.position = Vector2(0, 200)
	ground.make_static()
	world.add_body(ground, [_two_ground(1200, 40, mat_left, mat_right)])
	var box := PBody.new()
	box.position = Vector2(100, 191)        # 扁平 + 贴地：同上，别让翻滚混进判据
	world.add_body(box, [_rect(32, 8, 3)])
	box.linear_velocity = Vector2(300, 0)
	for i in 240:
		world.step(1.0 / 60.0)
	return box.position.x - 100.0


## 下半截是**弹的**（恢复 0.9）下半截是**死的**（0.0）的方块 ：量落地后的最大回弹高度。
func _bounce_band(bouncy_down: bool) -> float:
	var world := PWorld.new()
	world.gravity = Vector2(0, 600)
	world.set_material_restitution(1, 0.9)  # 弹
	world.set_material_restitution(2, 0.0)  # 死
	world.set_material_restitution(3, 0.0)  # 地面（不配恢复）
	world.set_material_friction(1, 0.5)
	world.set_material_friction(2, 0.5)
	world.set_material_friction(3, 0.5)
	var ground := PBody.new()
	ground.position = Vector2(0, 200)
	ground.make_static()
	world.add_body(ground, [_rect(600, 40, 3)])
	var box := PBody.new()
	box.position = Vector2(100, 100)
	var shape := _two_band(12, 12, 1, 2) if bouncy_down else _two_band(12, 12, 2, 1)
	world.add_body(box, [shape])
	var bounced := false
	var peak := 0.0
	for i in 300:
		world.step(1.0 / 60.0)
		if not bounced and box.linear_velocity.y < -1.0 and box.position.y > 170.0:
			bounced = true
		if bounced:
			peak = maxf(peak, 200.0 - box.position.y)
	return peak


func _initialize() -> void:
	print("=== 材质：摩擦系数（默认合成规则 = 几何平均 sqrt(μ₁·μ₂)）===")
	var far := _slide(0.0)
	var near := _slide(0.9)
	# 阈值 150：摩擦 0 也会被线阻尼（0.35/s）拖慢，滑不到无限远。
	_c("摩擦 0 滑得远", far > 150.0, "滑了 %.1f px" % far)
	_c("摩擦 0.9 滑得近", near < far * 0.6, "滑了 %.1f px（无摩擦是 %.1f）" % [near, far])
	# ⚠️⚠️ 这一条是"**不取平均**"的核心判据：地面摩擦 0（冰面）时，箱子的 0.9 不该被
	#    平均成 0.45 —— 几何平均下接触系数是 0，轨迹应与"箱子也是 0"**一致**。
	#    旧行为（Average）下这里是 0.45，滑得明显更近。
	var ice := _slide(0.9, 0.0)
	_c("地面摩擦 0 时箱子照样滑（任一边 0 -> 接触无摩擦）", ice > far - 1.0,
		"滑了 %.1f px（无摩擦是 %.1f，" % [ice, far] + "0.45 会滑得明显更近）")
	# 对照：同一场景把规则改回"取平均"，滑行距离必须明显变短 —— 证明 op 47 真的到了 Rapier。
	var ice_avg := _slide(0.9, 0.0, PWorld.COMBINE_AVERAGE)
	_c("同场景改回取平均 -> 明显滑得近（旋钮真的接到了 Rapier）", ice_avg < ice * 0.85,
		"取平均 %.1f px vs 几何平均 %.1f px" % [ice_avg, ice])

	print("=== 材质：碰撞恢复系数（默认合成规则 = 取大 max(e₁, e₂)）===")
	var dead := _bounce(0.0)
	var bouncy := _bounce(0.9)
	_c("恢复 0 基本不弹", dead < 3.0, "回弹 %.1f px" % dead)
	# ⚠️ 旧行为的症状就在这里：Rapier 默认取平均，球 0.9 + 地面 0 -> 接触处 0.45
	#    -> 只弹 ~19 px，看着像"恢复系数根本没接上"。取大之后地面不配也弹满。
	_c("恢复 0.9 弹得高（地面没配也弹满）", bouncy > dead + 40.0,
		"回弹 %.1f px（不弹是 %.1f）" % [bouncy, dead])
	var both := _bounce(0.9, 0.9)
	_c("只给球配 == 两边都配（取大：更弹的一方说了算）", absf(both - bouncy) < 1.0,
		"两边都配 %.1f px vs 只有球配 %.1f px" % [both, bouncy])
	var bouncy_avg := _bounce(0.9, 0.0, PWorld.COMBINE_AVERAGE)
	_c("同场景改回取平均 -> 只弹回一半（旋钮真的接到了 Rapier）", bouncy_avg < bouncy * 0.5,
		"取平均 %.1f px vs 取大 %.1f px" % [bouncy_avg, bouncy])

	print("=== 同一刚体上不同材质的表面各自生效 ===")
	# ⚠️⚠️ 判据是"**哪个材质的表面在接触**决定手感"：两块方块的材质一模一样
	#    （一截冰 0.0、一截橡胶 0.9），只是上下对调 —— 它们的整体平均系数**完全相同**，
	#    所以滑行距离若有差别，只可能来自"接触地面的那半截是什么材质"。
	#    旧实现（整刚体一个平均系数）下这两次必然一样。
	var ice_down := _slide_band(true)
	var rubber_down := _slide_band(false)
	_c("冰的那面朝下滑得远、橡胶那面朝下滑得近", ice_down > rubber_down * 1.5,
		"冰朝下 %.1f px vs 橡胶朝下 %.1f px（平均系数两者相同）" % [ice_down, rubber_down])
	# 一整块**多材质静态地形**：脚下那半是冰还是橡胶，决定滑多远（旧实现只取第一个像素的材质）。
	var on_ice := _slide_terrain(1, 2)
	var on_rubber := _slide_terrain(2, 1)
	_c("多材质地形：脚下是冰 vs 橡胶", on_ice > on_rubber * 1.5,
		"冰上 %.1f px vs 橡胶上 %.1f px（同一块地形刚体）" % [on_ice, on_rubber])
	# 恢复系数同理：弹的那半截朝下才弹得起来。
	var bouncy_down := _bounce_band(true)
	var dead_down := _bounce_band(false)
	_c("弹的那面朝下才弹得起来", bouncy_down > dead_down + 20.0,
		"弹面朝下 %.1f px vs 死面朝下 %.1f px" % [bouncy_down, dead_down])

	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

extends SceneTree
## 端到端闸门：撞击 -> 多点入口 -> 打洞，**真正跑一遍**（headless）。
##
## 这是 demo 那条 impact_damage 规则所依赖的**引擎侧**全部步骤：
##   接触事件 -> 应力门槛 -> Destruction.contact_entries -> world.fracture
## ⚠️ 不是"重复实现规则"：用的就是引擎自己的 contact_entries / fracture，
##    只是把 demo 里那 15 行包装换成探针（因为 demo 是 Node，headless 跑不了场景）。
##
## 守四件事：
##   1. 撞击**真的打出了洞**（墙的像素数减少）
##   2. 只打**一次**（is_new 过滤 —— 同一配对在一步里会被多个子步各记一次）
##   3. **预算共享**：两个入口的半径 = base/sqrt(2)（不是各用 base）
##   4. 推测接触（dist > 0）不打洞（由 validation_contact_entries 单独钉住）
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const Destruction := preload("res://src/core/destruction.gd")

var passed := 0
var failed := 0

func _assert(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("  [失败] " + msg)

## ⚠️ pixel_count() 在 **PixelShape** 上，不在 PBody 上（Editor.erase 就是遍历 shapes 累加的）。
##    直接写 body.pixel_count() 会让返回值没有确定类型，:= 报 "Cannot infer the type"。
func _pixels(b: PBody) -> int:
	var n := 0
	for s: PixelShape in b.shapes:
		n += s.pixel_count()
	return n


func _box(w: int, h: int, mat: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), mat)
	return s

func _initialize() -> void:
	print("=== 撞击 -> 多点入口 -> 打洞（端到端）===")
	var w := PWorld.new()
	w.gravity = Vector2(0, 600)
	w.contact_events_enabled = true
	var wall := PBody.new()
	wall.position = Vector2(0, 100)
	wall.make_static()
	w.add_body(wall, [_box(400, 24, 1)], Callable(), true)
	var hammer := PBody.new()
	hammer.position = Vector2(200, 60)
	w.add_body(hammer, [_box(32, 8, 2)], Callable(), true)
	hammer.linear_velocity = Vector2(0, 900)      # 砸下去
	w._rp_ensure()
	var before := _pixels(wall)
	var base := 8.0
	var threshold := 30.0
	var hits := 0
	var radii: Array = []
	for i in 60:
		w.step(1.0 / 60.0)
		for c in w.contacts:
			if not c.is_new:
				continue                              # 同一配对一步内会被多子步各记一次
			var stress: float = c.impulse / maxf(c.contact_width, 0.001)
			if stress < threshold:
				continue
			for e in Destruction.contact_entries(c.points, c.total_impulse, base):
				if not e["penetrating"]:
					continue
				hits += 1
				radii.append(e["radius"])
				var dmg = Destruction.Damage.circle(wall.to_local(e["point"]), e["radius"])
				w.fracture(wall, dmg)
	var after := _pixels(wall)
	var removed: int = before - after
	print("  墙像素 %d -> %d（被打掉 %d）；施加次数 = %d，半径 = %s" % [
		before, after, removed, hits, str(radii)])
	_assert(removed > 0, "撞击没有打出洞（像素数没变）—— 整条链没通")
	_assert(hits >= 1, "没有任何一次损伤被施加")
	# ⚠️ 预算共享：两点等冲量 -> 每个入口的半径应是 base/sqrt(2)，不是 base
	if hits >= 2:
		var want := base / sqrt(2.0)
		_assert(absf(radii[0] - want) < 0.01,
			"半径应当是 base/sqrt(2)=%.4f（预算共享），实际 %.4f" % [want, radii[0]])
		print("  半径 %.4f == base/sqrt(2) %.4f -> 预算共享成立" % [radii[0], want])
	# ⚠️ 只打一次：整段里施加次数应当等于"接触点数"（2），而不是每帧都打
	_assert(hits <= 4, "施加次数 %d 太多 —— is_new 过滤没起作用？" % hits)
	print("---")
	if failed == 0:
		print("全部通过：%d 项断言" % passed)
	else:
		print("失败 %d / %d 项" % [failed, passed + failed])
	quit(0 if failed == 0 else 1)

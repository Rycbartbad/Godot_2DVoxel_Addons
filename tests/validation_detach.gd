extends SceneTree
## detach（摘除）的闸门：**体素个数守恒**。
##
## 守的是设计分工（不是实现细节）：
##   · detach   = 命中的像素**变成碎片**（新刚体）-> 总像素数**不变**
##   · fracture = 命中的像素**消失**             -> 总像素数**下降**
## 笔刷擦除走 fracture（擦掉就是擦掉），撞击/切断走 detach（Teardown 那样，碎块留下来）。
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


## 全场总像素数（跨所有刚体 —— 守恒是**全场**的不变量）
func _total(w) -> int:
	var n := 0
	for b in w.bodies:
		for s in b.shapes:
			n += s.pixel_count()
	return n


func _slab(w) -> PBody:
	var b := PBody.new()
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, 40, 40), 1)
	w.add_body(b, [s], Callable(), true)
	return b


func _initialize() -> void:
	print("=== detach：体素个数守恒 ===")
	# ① 内部挖洞（不断开）：像素应当**全部变成碎片**
	var w1 := PWorld.new()
	var b1 := _slab(w1)
	var before1 := _total(w1)
	w1.detach(b1, Destruction.Damage.circle(Vector2(20, 20), 6.0))
	var after1 := _total(w1)
	print("  内部挖洞：%d -> %d（刚体 %d）" % [before1, after1, w1.bodies.size()])
	_assert(after1 == before1, "内部挖洞后总数应当不变，实际 %d -> %d" % [before1, after1])
	_assert(w1.bodies.size() > 1, "应当生成了碎片刚体，实际刚体数 %d" % w1.bodies.size())

	# ② 从边上切断：切下来的那块也应当守恒
	var w2 := PWorld.new()
	var b2 := _slab(w2)
	var before2 := _total(w2)
	w2.detach(b2, Destruction.Damage.rect(Vector2(20, 0), Vector2(20, 20)))
	var after2 := _total(w2)
	print("  边缘切断：%d -> %d（刚体 %d）" % [before2, after2, w2.bodies.size()])
	_assert(after2 == before2, "边缘切断后总数应当不变，实际 %d -> %d" % [before2, after2])

	# ③ 对照组：fracture **不**守恒（这是它该有的行为）
	var w3 := PWorld.new()
	var b3 := _slab(w3)
	var before3 := _total(w3)
	w3.fracture(b3, Destruction.Damage.circle(Vector2(20, 20), 6.0))
	var after3 := _total(w3)
	print("  对照 fracture：%d -> %d（刚体 %d）" % [before3, after3, w3.bodies.size()])
	_assert(after3 < before3, "fracture 应当把像素删掉（不守恒），实际 %d -> %d" % [before3, after3])

	print("---")
	if failed == 0:
		print("全部通过：%d 项断言" % passed)
	else:
		print("失败 %d / %d 项" % [failed, passed + failed])
	quit(0 if failed == 0 else 1)

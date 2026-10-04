extends SceneTree
## 验证 detach：**体素个数守恒**（命中的像素变成碎片，而不是消失）。
## 对照：fracture 会让总数下降（挖洞）。
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const Destruction := preload("res://src/core/destruction.gd")

func _total(w) -> int:
	var n := 0
	for b in w.bodies:
		for s in b.shapes:
			n += s.pixel_count()
	return n

func _make(w, use_detach: bool) -> int:
	var b := PBody.new()
	b.position = Vector2(0, 0)
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, 40, 40), 1)
	w.add_body(b, [s], Callable(), true)
	var before := _total(w)
	# 在正中打一个洞（不碰边界 -> 不会断开）
	var dmg = Destruction.Damage.circle(Vector2(20, 20), 6.0)
	if use_detach:
		w.detach(b, dmg)
	else:
		w.fracture(b, dmg)
	return before

func _initialize() -> void:
	var w1 := PWorld.new()
	var before1 := _make(w1, true)
	var after1 := _total(w1)
	print("detach  ：%d -> %d（差值 %d，刚体数 %d）" % [before1, after1, after1 - before1, w1.bodies.size()])
	var w2 := PWorld.new()
	var before2 := _make(w2, false)
	var after2 := _total(w2)
	print("fracture：%d -> %d（差值 %d，刚体数 %d）" % [before2, after2, after2 - before2, w2.bodies.size()])
	print("=> detach 守恒: %s；fracture 不守恒: %s" % [str(after1 == before1), str(after2 < before2)])
	quit(0)

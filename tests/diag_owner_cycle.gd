extends SceneTree
## 实验：断掉 PixelShape.owner_body（shape -> body 的反向引用）后，泄漏是否消失？
## 这是排查 B 的判定实验。
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _initialize() -> void:
	var mode := OS.get_environment("BREAK_OWNER")
	var w := PWorld.new()
	w._rp_ensure()
	var b := PBody.new()
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, 8, 8), 1)
	w.add_body(b, [s], Callable(), true)
	print("刚体数 " + str(w.bodies.size()) + "，owner_body 已写 = " + str(s.owner_body != null))
	if mode == "1":
		for bb in w.bodies:
			for ss in bb.shapes:
				ss.owner_body = null
		print("已断掉 owner_body")
	w = null
	b = null
	quit(0)

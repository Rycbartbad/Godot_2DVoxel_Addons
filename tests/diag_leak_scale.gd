extends SceneTree
## 泄漏是否随刚体数线性增长？（决定根因是不是 body/shape/chunk 图里的环）
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _initialize() -> void:
	var n := int(OS.get_environment("NBODIES"))
	var w := PWorld.new()
	w._rp_ensure()
	for i in n:
		var b := PBody.new()
		b.position = Vector2(i * 20, 0)
		var s := PixelShape.new()
		s.fill_rect(Rect2i(0, 0, 8, 8), 1)
		w.add_body(b, [s], Callable(), true)
	print("刚体数 = " + str(w.bodies.size()))
	w = null
	quit(0)

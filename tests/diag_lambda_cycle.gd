extends SceneTree
## 判定实验：断掉 PWorld 自己字段里缓存的三个 lambda（它们捕获 self），泄漏是否消失？
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _initialize() -> void:
	var mode := OS.get_environment("BREAK_FNS")
	var w := PWorld.new()
	w._rp_ensure()
	var b := PBody.new()
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, 8, 8), 1)
	w.add_body(b, [s], Callable(), true)
	print("建好了；三个缓存是否有效: d=" + str(w._friction_fn.is_valid()) + " r=" + str(w._restitution_fn.is_valid()))
	if mode == "1":
		w._friction_fn = Callable()
		w._restitution_fn = Callable()
		print("已清掉两个缓存 lambda")
	w = null
	b = null
	quit(0)

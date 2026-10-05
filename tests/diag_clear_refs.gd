extends SceneTree
## 判定：泄漏是不是**测试脚本自己的局部引用**造成的？
## CLEAR_REFS=1 时在 quit 前把所有引用置 null。
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _initialize() -> void:
	var clear := OS.get_environment("CLEAR_REFS") == "1"
	var w := PWorld.new()
	w._rp_ensure()
	var b := PBody.new()
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, 8, 8), 1)
	w.add_body(b, [s], Callable(), true)
	print("建好了；CLEAR_REFS=" + str(clear))
	if clear:
		# 把能清的都清掉（数组里的 shape 引用也要清）
		w.bodies.clear()
		b.shapes.clear()
		s.chunks.clear()
		w = null
		b = null
		s = null
		print("引用已全部置 null")
	quit(0)

extends SceneTree
## 分步复现：每步打一行，定位 mode=body 卡在哪。
## ⚠️ 不用 --verbose（它的输出量会把管道拖死）。
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _initialize() -> void:
	print("1 开始")
	var w := PWorld.new()
	print("2 PWorld 建好")
	w._rp_ensure()
	print("3 原生实例拿到: " + str(w._rp != null))
	var b := PBody.new()
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, 8, 8), 1)
	print("4 形状建好，像素 " + str(s.pixel_count()))
	print("5 调 density_callable...")
	var cb := w.density_callable()
	print("6 callable 有效: " + str(cb.is_valid()))
	print("7 直接调一次: " + str(cb.call(1)))
	print("8 调 add_body...")
	w.add_body(b, [s], Callable(), true)
	print("9 add_body 完成，刚体数 " + str(w.bodies.size()))
	quit(0)

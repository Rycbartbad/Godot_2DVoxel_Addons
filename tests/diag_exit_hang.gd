extends SceneTree
## 判定：卡在运行期还是退出路径。
## 关键：quit(0) 之前打一行 —— 它出现了就说明运行期是好的。
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _initialize() -> void:
	var w := PWorld.new()
	w._rp_ensure()
	var b := PBody.new()
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, 8, 8), 1)
	w.add_body(b, [s], Callable(), true)
	print("A 运行期完成（刚体数 " + str(w.bodies.size()) + "）")
	# 按你们的笔记：清理引用
	w = null
	b = null
	print("B 引用已清")
	quit(0)

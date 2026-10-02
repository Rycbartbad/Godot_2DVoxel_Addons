extends SceneTree
## 管道验证：DLL 是否被加载、类是否注册、能否实例化
func _initialize() -> void:
	print("ClassDB.class_exists('FastPhys') = ", ClassDB.class_exists("FastPhys"))
	if ClassDB.class_exists("FastPhys"):
		var o: Variant = ClassDB.instantiate("FastPhys")
		print("实例化结果 = ", o, "  类型 = ", (o.get_class() if o != null else "null"))
		if o != null and o is RefCounted:
			print("是 RefCounted ✓ 引用计数可管理")
	quit(0)

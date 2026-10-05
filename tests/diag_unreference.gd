extends SceneTree
## 绕过 Godot 的实例化多引用：RefCounted.unreference() 能不能从 GDScript 调？
## 计数 2 时调一次 -> 1（不会误释放），于是退出时那份搁置的引用就没了。
func _initialize() -> void:
	var rp = ClassDB.instantiate("RapierPhys")
	print("创建后 = " + str(rp.get_reference_count()))
	var has: bool = rp.has_method("unreference")
	print("有 unreference 方法 = " + str(has))
	if has:
		rp.unreference()
		print("调一次后 = " + str(rp.get_reference_count()))
	# 也看看 reference 是否可用（对照）
	print("有 reference 方法 = " + str(rp.has_method("reference")))
	quit(0)

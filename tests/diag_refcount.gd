extends SceneTree
## 量 RapierPhys 的引用计数，与普通 RefCounted 对照。
## 若 RapierPhys 是 2（而普通是 1），多出来的那个引用就在扩展的 create_instance_func 里。
func _initialize() -> void:
	var rp = ClassDB.instantiate("RapierPhys")
	print("RapierPhys: 是 RefCounted = " + str(rp is RefCounted))
	print("RapierPhys: get_reference_count = " + str(rp.get_reference_count()))
	var rc := RefCounted.new()
	print("普通 RefCounted: get_reference_count = " + str(rc.get_reference_count()))
	var ref := WeakRef.new()
	print("普通 WeakRef: get_reference_count = " + str(ref.get_reference_count()))
	# 再看一次（把 rp 放进一个数组会不会 +1）
	var arr := [rp]
	print("放进数组后 = " + str(rp.get_reference_count()))
	arr.clear()
	print("数组清空后 = " + str(rp.get_reference_count()))
	quit(0)

extends SceneTree
## 探测 GDScript 里 WorkerThreadPool 的安全写法：
## 问题是 Godot 的 Array / Packed*Array 都是写时复制(COW)，
## lambda 捕获会让引用计数 > 1，于是子线程里的写入可能落到副本上而丢失。
func _initialize() -> void:
	print("CPU 核心: ", OS.get_processor_count())

	# A) 捕获 Array，按索引整体赋值
	var slots := []
	slots.resize(8)
	var mtx := Mutex.new()
	var w1 := func(t: int) -> void:
		var local := [t * 10, t * 10 + 1]
		mtx.lock()
		slots[t] = local
		mtx.unlock()
	var g1 := WorkerThreadPool.add_group_task(w1, 8, -1, false, "probe_a")
	WorkerThreadPool.wait_for_group_task_completion(g1)
	var lost_a := 0
	for i in 8:
		if slots[i] == null or slots[i][0] != i * 10:
			lost_a += 1
	print("A) 捕获 Array 整体赋值: ", "OK" if lost_a == 0 else "丢了 %d 个" % lost_a)

	# B) 捕获 PackedInt64Array，按索引写元素
	var arr := PackedInt64Array()
	arr.resize(8)
	var mtx2 := Mutex.new()
	var w2 := func(t: int) -> void:
		mtx2.lock()
		arr[t] = t * 7
		mtx2.unlock()
	var g2 := WorkerThreadPool.add_group_task(w2, 8, -1, false, "probe_b")
	WorkerThreadPool.wait_for_group_task_completion(g2)
	var bad_b := 0
	for i in 8:
		if arr[i] != i * 7:
			bad_b += 1
	print("B) 捕获 PackedInt64Array 写元素: ", "OK" if bad_b == 0 else "丢了 %d 个" % bad_b, "  ", arr)

	# C) 无锁（只说明必须加锁，这里只统计是否损坏）
	var slots3 := []
	slots3.resize(64)
	var w3 := func(t: int) -> void:
		slots3[t] = t
	var g3 := WorkerThreadPool.add_group_task(w3, 64, -1, false, "probe_c")
	WorkerThreadPool.wait_for_group_task_completion(g3)
	var lost_c := 0
	for i in 64:
		if slots3[i] != i:
			lost_c += 1
	print("C) 无锁 64 并发写: ", "OK" if lost_c == 0 else "丢了 %d 个" % lost_c)
	quit(0)

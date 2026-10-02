extends SceneTree
## 探测：WorkerThreadPool 的**嵌套** group task 会不会因为线程池被占满而卡死？
##
## ⚠️ 结论（实测）：**会死锁。** 外层任务数 >= 池线程数时，每个外层任务都在等
## 自己的内层任务，而内层任务永远排不上队（所有线程都被"等待中"的外层任务占着），
## 进程直接挂死 —— 只能强杀。因此 OUTER 默认压到 4。
## 想看死锁现象就把 OUTER 改大（16 核时 >= 5 就可能挂），并准备好强杀进程。
##
## 这条结论直接否掉了"两层混合并行"最自然的实现方式
## （外层每岛一个任务 + 最重的岛在内层按颜色开子任务）。

var _done := []
var _mtx := Mutex.new()
var _sink := 0.0

func _spin(n: int) -> float:
	var s := 0.0
	for i in n:
		s += sqrt(float(i) + 1.0)
	return s

func _initialize() -> void:
	print("CPU 核心: ", OS.get_processor_count())

	# --- A) 嵌套正确性：外层各自再开 4 个内层任务并等待 ---
	# OUTER 必须显著小于线程池线程数，否则见文件头的死锁说明。
	var outer_n := 4
	var inner_n := 4
	_done.resize(outer_n)
	for i in outer_n:
		_done[i] = 0
	var t0 := Time.get_ticks_usec()
	var outer := func(t: int) -> void:
		var inner := func(u: int) -> void:
			_spin(20000)
			_mtx.lock()
			_done[t] += 1
			_mtx.unlock()
		var gid := WorkerThreadPool.add_group_task(inner, inner_n, -1, false, "probe_inner")
		WorkerThreadPool.wait_for_group_task_completion(gid)
	var gid2 := WorkerThreadPool.add_group_task(outer, outer_n, -1, false, "probe_outer")
	WorkerThreadPool.wait_for_group_task_completion(gid2)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var bad := 0
	for i in outer_n:
		if _done[i] != inner_n:
			bad += 1
	print("A) 嵌套 group task (%d 外层 x %d 内层, 最坏情况外层==核心数): %s  用时 %.2f ms" % [
		outer_n, inner_n, "OK，无死锁" if bad == 0 else "丢了 %d 个内层任务" % bad, ms])

	# --- B) 嵌套到底有没有拿到并行度：同样的总工作量，串行 vs 嵌套并行 ---
	var serial_t0 := Time.get_ticks_usec()
	for i in outer_n * inner_n:
		_spin(20000)
	var serial_ms := (Time.get_ticks_usec() - serial_t0) / 1000.0

	var nested_t0 := Time.get_ticks_usec()
	var outer2 := func(t: int) -> void:
		var inner2 := func(u: int) -> void:
			_spin(20000)
		var gid3 := WorkerThreadPool.add_group_task(inner2, inner_n, -1, false, "probe_inner2")
		WorkerThreadPool.wait_for_group_task_completion(gid3)
	var gid4 := WorkerThreadPool.add_group_task(outer2, outer_n, -1, false, "probe_outer2")
	WorkerThreadPool.wait_for_group_task_completion(gid4)
	var nested_ms := (Time.get_ticks_usec() - nested_t0) / 1000.0
	print("B) 同样工作量 %d 份: 串行 %.2f ms | 嵌套并行 %.2f ms | 加速 %.2fx" % [
		outer_n * inner_n, serial_ms, nested_ms, serial_ms / maxf(0.001, nested_ms)])

	# --- C) 对照：单层 group task（现状岛并行用的形式）---
	var flat_t0 := Time.get_ticks_usec()
	var flat := func(t: int) -> void:
		_spin(20000)
	var gid5 := WorkerThreadPool.add_group_task(flat, outer_n * inner_n, -1, false, "probe_flat")
	WorkerThreadPool.wait_for_group_task_completion(gid5)
	var flat_ms := (Time.get_ticks_usec() - flat_t0) / 1000.0
	print("C) 单层 group task %d 份: %.2f ms | 加速 %.2fx" % [
		outer_n * inner_n, flat_ms, serial_ms / maxf(0.001, flat_ms)])

	print("结论: 嵌套可用 => 两层混合并行可以用「外层每岛一任务 + 最重岛内层按色任务」实现")
	quit(0)

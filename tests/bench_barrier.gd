extends SceneTree
## 假设：WorkerThreadPool 把线程分成"高优先级 / 低优先级"两组，
## 低优先级那一组只占 ~30%（项目设置 threading/worker_pool/low_priority_thread_ratio）。
## 而 _parallel_solve / solve_colored 传的是 high_priority=false —— 于是整套物理并行
## 只能用到 4 个线程，这就是并行度上不去的真正原因。
## 直接对比 high_priority 两档。

func _spin(iters: int) -> float:
	var s := 0.0
	for i in iters:
		s += sqrt(float(i) + 1.0)
	return s

func _probe(high: bool) -> void:
	var n := 128
	var recs: Array = []
	recs.resize(n)
	var mtx := Mutex.new()
	var t0 := Time.get_ticks_usec()
	var w := func(t: int) -> void:
		var s0 := Time.get_ticks_usec()
		var r := _spin(20000)
		var e0 := Time.get_ticks_usec()
		mtx.lock()
		recs[t] = [OS.get_thread_caller_id(), s0, e0, r]
		mtx.unlock()
	var gid := WorkerThreadPool.add_group_task(w, n, -1, high, "probe")
	WorkerThreadPool.wait_for_group_task_completion(gid)
	var total_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var threads := {}
	var work_us := 0.0
	var first := 1.0e18
	var last := 0.0
	for i in n:
		var r: Array = recs[i]
		threads[r[0]] = true
		work_us += float(r[2] - r[1])
		first = minf(first, float(r[1]))
		last = maxf(last, float(r[2]))
	var span_ms := (last - first) / 1000.0
	print("high_priority=%-5s | 线程数 %2d | 墙钟 %8.2f ms | 合计 %8.2f ms | 实测并行度 %5.2fx | 串行估计 %8.2f ms" % [
		str(high), threads.size(), total_ms, work_us / 1000.0,
		(work_us / 1000.0) / maxf(0.001, span_ms), work_us / 1000.0])

func _initialize() -> void:
	print("=== high_priority 对 group task 线程铺开的影响（%d 个元素）===" % 128)
	print("CPU 核心数（Godot 视角）: ", OS.get_processor_count())
	# 交替测两轮，避免顺序偏差
	_probe(false)
	_probe(true)
	_probe(false)
	_probe(true)
	quit(0)

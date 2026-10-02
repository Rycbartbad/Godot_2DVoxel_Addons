extends SceneTree
## 为什么 high_priority 在真实求解器上反而更慢（0.43x），
## 但在合成基准上更快（15x）？差别在**每个任务的工作量**：
## 合成基准每个元素 ~1.2 ms，求解器每个岛只有 ~150 us。
## 假设：线程唤醒成本固定，任务太小的时候，高优先级把 16 个线程全部叫醒
## （每个任务一次唤醒风暴），成本超过收益。
## 这个实验直接扫"元素数 x 每个元素的工作量 x 优先级"。

func _initialize() -> void:
	print("=== 任务粒度 vs 优先级（元素数固定 37，模拟 37 个岛）===")
	print("%-12s %-10s %-10s %-10s %-8s" % ["工作量", "优先级", "墙钟ms", "并行度", "线程数"])
	# 先标定：多少次自旋 ≈ 1 us
	var t0 := Time.get_ticks_usec()
	var s := 0.0
	for i in 200000:
		s += sqrt(float(i) + 1.0)
	var per_spin := float(Time.get_ticks_usec() - t0) / 200000.0
	print("标定: 1 次自旋 ≈ %.4f us (200k 次耗时 %.1f ms)" % [per_spin, float(Time.get_ticks_usec() - t0) / 1000.0])
	for work in [200, 1000, 5000, 20000, 80000]:
		for high in [false, true]:
			var best_wall := 1.0e18
			var best_par := 0.0
			var best_th := 0
			for rep in 3:
				var n := 37
				var recs: Array = []
				recs.resize(n)
				var mtx := Mutex.new()
				var tt := Time.get_ticks_usec()
				var w := func(t: int) -> void:
					var s0 := Time.get_ticks_usec()
					var acc := 0.0
					for i in work:
						acc += sqrt(float(i) + 1.0)
					var e0 := Time.get_ticks_usec()
					mtx.lock()
					recs[t] = [OS.get_thread_caller_id(), s0, e0, acc]
					mtx.unlock()
				var gid := WorkerThreadPool.add_group_task(w, n, -1, high, "gran")
				WorkerThreadPool.wait_for_group_task_completion(gid)
				var wall := (Time.get_ticks_usec() - tt) / 1000.0
				var th := {}
				var wu := 0.0
				var f := 1.0e18
				var l := 0.0
				for i in n:
					var r: Array = recs[i]
					th[r[0]] = true
					wu += float(r[2] - r[1])
					f = minf(f, float(r[1]))
					l = maxf(l, float(r[2]))
				var par := (wu / 1000.0) / maxf(0.001, (l - f) / 1000.0)
				if wall < best_wall:
					best_wall = wall
					best_par = par
					best_th = th.size()
			print("%-12s %-10s %-10.3f %-10.2f %-8d" % [
				"%.0f us" % (per_spin * float(work)), str(high), best_wall, best_par, best_th])
	quit(0)

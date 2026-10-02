extends SceneTree
## 决定性实验：GDScript 的**成员方法调用**在 worker 线程之间会不会串行化？
##
## 线索：同一个微基准里，"lambda 内联循环"能拿到 15x（16 线程），
## 而"lambda 里调 self._spin()"只有 1.0x。而求解器里全是成员方法调用
## （velocity_at / _apply / _solve_block_normal）—— 如果是这样，物理并行
## 根本不可能有量级提升，真正的出路就不是并行。
##
## 四种调用形态，同样的总工作量，都在 worker 线程里执行。

class Helper:
	extends RefCounted
	func spin(n: int) -> float:
		var s := 0.0
		for i in n:
			s += sqrt(float(i) + 1.0)
		return s
	static func spin_static(n: int) -> float:
		var s := 0.0
		for i in n:
			s += sqrt(float(i) + 1.0)
		return s

var _helper := Helper.new()

func _spin(n: int) -> float:
	var s := 0.0
	for i in n:
		s += sqrt(float(i) + 1.0)
	return s

func _spin_static(n: int) -> float:
	var s := 0.0
	for i in n:
		s += sqrt(float(i) + 1.0)
	return s

## mode: 0=内联  1=self 成员方法  2=self 静态方法  3=另一个对象的方法
func _run(mode: int, n_elems: int, work: int, high: bool) -> Array:
	var recs: Array = []
	recs.resize(n_elems)
	var mtx := Mutex.new()
	var t0 := Time.get_ticks_usec()
	var w := func(t: int) -> void:
		var s0 := Time.get_ticks_usec()
		var r := 0.0
		match mode:
			0:
				var s := 0.0
				for i in work:
					s += sqrt(float(i) + 1.0)
				r = s
			1: r = _spin(work)
			2: r = _spin_static(work)
			3: r = _helper.spin(work)
		var e0 := Time.get_ticks_usec()
		mtx.lock()
		recs[t] = [OS.get_thread_caller_id(), s0, e0, r]
		mtx.unlock()
	var gid := WorkerThreadPool.add_group_task(w, n_elems, -1, high, "vmcall")
	WorkerThreadPool.wait_for_group_task_completion(gid)
	var wall := (Time.get_ticks_usec() - t0) / 1000.0
	var threads := {}
	var work_us := 0.0
	var first := 1.0e18
	var last := 0.0
	for i in n_elems:
		var r2: Array = recs[i]
		threads[r2[0]] = true
		work_us += float(r2[2] - r2[1])
		first = minf(first, float(r2[1]))
		last = maxf(last, float(r2[2]))
	var span := (last - first) / 1000.0
	return [threads.size(), wall, work_us / 1000.0, (work_us / 1000.0) / maxf(0.001, span)]

func _line(name: String, mode: int, n: int, work: int, high: bool) -> void:
	var best := 1.0e18
	var best_par := 0.0
	var th := 0
	# 交叉重复：高/低优先级各自跑两次取最好
	for r in 3:
		var res := _run(mode, n, work, high)
		if res[1] < best:
			best = res[1]
			best_par = res[3]
			th = res[0]
	print("  %-22s 线程 %2d | 墙钟 %8.2f ms | 合计 %8.2f ms | 并行度 %5.2fx" % [
		name, th, best, best_par * (best), best_par])

func _initialize() -> void:
	var n := 128
	var work := 20000
	print("=== GDScript 调用形态 vs 并行度（%d 元素 x %d 自旋）===" % [n, work])
	print("-- high_priority = true --")
	_line("内联循环", 0, n, work, true)
	_line("self 成员方法", 1, n, work, true)
	_line("self 成员(非static)", 3, n, work, true)
	_line("另一个对象的方法", 3, n, work, true)
	print("-- high_priority = false --")
	_line("内联循环", 0, n, work, false)
	_line("self 成员方法", 1, n, work, false)
	quit(0)

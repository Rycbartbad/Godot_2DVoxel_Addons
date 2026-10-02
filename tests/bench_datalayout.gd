extends SceneTree
## 决定性实验：**数据布局**能不能解开两个枷锁？
##
## 已知：对象属性读写在 16 线程并发下单元耗时膨胀 93 倍（坑 19），
## 于是求解器的并行度被迫停在 ~4 线程。
## 这里面有两个可以独立量出来的量：
##   (1) 串行成本：PackedFloat64Array 元素读写 vs 对象属性读写，谁快？
##   (2) 并发膨胀：前者在 16 线程下会不会也膨胀？
## 如果 PackedArray 又快又不膨胀，那么"数据导向改写"就是语言层面最大的一条路
## （串行变快 + 并行度从 4 线程解锁到 16 线程）。
##
## 注意：这里只比 **GDScript 层面的访存形式**，不涉及任何模拟语义。

class Node2:
	extends RefCounted
	var v := Vector2.ZERO

var _sink := 0.0

## mode: 0=纯算术  1=对象属性  2=PackedFloat64Array  3=普通 Array
func _work(mode: int, seed_id: int, iters: int, m: int) -> float:
	var acc := 0.0
	match mode:
		0:
			for i in iters:
				acc += sqrt(float(i % 97) + 1.0)
		1:
			var o := Node2.new()
			for i in iters:
				o.v = o.v + Vector2(0.5, 0.25)
				acc += o.v.x
		2:
			var arr := PackedFloat64Array()
			arr.resize(m * 3)
			for i in iters:
				var k := (i % m) * 3
				arr[k] = arr[k] + 0.5
				arr[k + 1] = arr[k + 1] + 0.25
				acc += arr[k]
		3:
			var a: Array = []
			a.resize(m * 3)
			for j in m * 3:
				a[j] = 0.0
			for i in iters:
				var k2 := (i % m) * 3
				a[k2] = a[k2] + 0.5
				a[k2 + 1] = a[k2 + 1] + 0.25
				acc += a[k2]
	return acc

func _serial(mode: int, n: int, iters: int, m: int) -> float:
	var t0 := Time.get_ticks_usec()
	for i in n:
		_sink += _work(mode, i, iters, m)
	return float(Time.get_ticks_usec() - t0) / float(n)

func _parallel(mode: int, n: int, iters: int, m: int, high: bool, reps: int) -> float:
	var best := 1.0e18
	for rep in reps:
		var recs: Array = []
		recs.resize(n)
		var mtx := Mutex.new()
		var w := func(t: int) -> void:
			var s0 := Time.get_ticks_usec()
			var r := _work(mode, t, iters, m)
			var e0 := Time.get_ticks_usec()
			mtx.lock()
			recs[t] = [float(e0 - s0), r]
			mtx.unlock()
		var gid := WorkerThreadPool.add_group_task(w, n, -1, high, "layout")
		WorkerThreadPool.wait_for_group_task_completion(gid)
		var sum := 0.0
		for i in n:
			var r: Array = recs[i]
			sum += r[0]
			_sink += r[1]
		best = minf(best, sum / float(n))
	return best

func _initialize() -> void:
	var n := 37
	var iters := 20000
	var m := 8
	print("=== 数据布局：串行成本 & 16 线程并发膨胀（%d 元素 x %d 次迭代）===" % [n, iters])
	print("%-22s %-14s %-14s %-10s %s" % ["访存形式", "串行 us/元素", "并行 us/元素", "并发倍数", "串行相对纯算术"])
	var names := ["纯算术(对照组)", "对象属性 (AoS)", "PackedFloat64Array", "普通 Array"]
	var serials: Array = []
	for mode in 4:
		var s := _serial(mode, n, iters, m)
		serials.append(s)
	for mode2 in 4:
		var p := _parallel(mode2, n, iters, m, true, 3)
		print("%-22s %-14.1f %-14.1f %-10.2fx %.2fx" % [
			names[mode2], serials[mode2], p, p / maxf(0.001, serials[mode2]),
			serials[mode2] / serials[0]])
	print("\n=== 对照：低优先级（4 线程）===")
	for mode3 in [1, 2]:
		var p2 := _parallel(mode3, n, iters, m, false, 3)
		print("%-22s 串行 %8.1f -> 并行 %8.1f  (%.2fx)" % [
			names[mode3], serials[mode3], p2, p2 / maxf(0.001, serials[mode3])])
	quit(0)

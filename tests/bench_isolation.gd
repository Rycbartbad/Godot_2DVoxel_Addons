extends SceneTree
## 为什么"并发跑求解器"会让每个任务自己的耗时涨 17 倍？
## （实测：低优先级 4 线程时各任务合计 26.65 ms；高优先级 16 线程时 452.66 ms，
##   而两者跑的代码完全一样 —— 唯一变量是**同时运行的线程数**。）
## 逐项排除：同样的 37 个元素、同样的迭代次数，只换工作内容。
## 指标 = 每个元素自己的耗时（并行时 / 串行时），>1 说明"并发让它变慢了"。

class Node2:
	extends RefCounted
	var v := Vector2.ZERO
	var w := 0.0

var _objs: Array = []

static func _static_rw(o, iters: int) -> float:
	var acc := 0.0
	for i in iters:
		o.v = o.v + Vector2(0.5, 0.25)
		acc += o.v.x
	return acc

func _instance_rw(o, iters: int) -> float:
	var acc := 0.0
	for i in iters:
		o.v = o.v + Vector2(0.5, 0.25)
		acc += o.v.x
	return acc

## mode: 0=纯算术  1=自有对象读写  2=静态函数里读写  3=成员函数里读写
func _element_work(mode: int, idx: int, iters: int) -> float:
	var acc := 0.0
	match mode:
		0:
			var x := 0.0
			for i in iters:
				x += sqrt(float(i % 97) + 1.0)
			acc = x
		1:
			var o: Node2 = _objs[idx]
			for i in iters:
				o.v = o.v + Vector2(0.5, 0.25)
				acc += o.v.x
		2:
			acc = _static_rw(_objs[idx], iters)
		3:
			acc = _instance_rw(_objs[idx], iters)
	return acc

func _make_objs(n: int) -> void:
	_objs = []
	for i in n:
		_objs.append(Node2.new())

## 串行跑一遍，返回每个元素的平均耗时 us
func _serial(mode: int, n: int, iters: int) -> float:
	_make_objs(n)
	var t0 := Time.get_ticks_usec()
	for i in n:
		_element_work(mode, i, iters)
	return float(Time.get_ticks_usec() - t0) / float(n)

## 并行跑一遍，返回"每个元素自己的耗时"的平均值 us
func _parallel(mode: int, n: int, iters: int, high: bool) -> float:
	_make_objs(n)
	var recs: Array = []
	recs.resize(n)
	var mtx := Mutex.new()
	var w := func(t: int) -> void:
		var s0 := Time.get_ticks_usec()
		var r := _element_work(mode, t, iters)
		var e0 := Time.get_ticks_usec()
		mtx.lock()
		recs[t] = float(e0 - s0)
		mtx.unlock()
	var gid := WorkerThreadPool.add_group_task(w, n, -1, high, "iso")
	WorkerThreadPool.wait_for_group_task_completion(gid)
	var sum := 0.0
	for i in n:
		sum += recs[i]
	return sum / float(n)

func _initialize() -> void:
	var n := 37
	var iters := 20000
	print("=== 37 个元素 x %d 次迭代：并发对**单元耗时**的影响 ===" % iters)
	print("%-22s %-12s %-12s %s" % ["工作内容", "串行 us/元素", "并行 us/元素", "并发倍数"])
	for spec in [[0, "纯算术"], [1, "自有对象属性读写"], [2, "静态函数里读写"], [3, "成员函数里读写"]]:
		var s_ms := _serial(spec[0], n, iters)
		var p_ms := _parallel(spec[0], n, iters, true)
		print("%-22s %-12.1f %-12.1f %.2fx" % [spec[1], s_ms, p_ms, p_ms / maxf(0.001, s_ms)])
	print("\n=== 对照：低优先级（4 线程）===")
	for spec2 in [[0, "纯算术"], [1, "自有对象属性读写"], [3, "成员函数里读写"]]:
		var s2 := _serial(spec2[0], n, iters)
		var p2 := _parallel(spec2[0], n, iters, false)
		print("%-22s %-12.1f %-12.1f %.2fx" % [spec2[1], s2, p2, p2 / maxf(0.001, s2)])
	quit(0)

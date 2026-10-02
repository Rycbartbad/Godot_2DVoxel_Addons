extends SceneTree
## 微基准：把数据写进打包缓冲的三种方式
##   1) PackedByteArray.encode_double（现在的做法）
##   2) PackedFloat64Array 直接下标写
##   3) PackedFloat64Array 直接下标读
func _initialize() -> void:
	var N := 8500          # 约等于 frag:500 的每步字段数
	var REP := 20
	var a := PackedByteArray()
	a.resize(N * 8)
	var b := PackedFloat64Array()
	b.resize(N)

	var best1 := 1 << 30
	for r in REP:
		var t0 := Time.get_ticks_usec()
		for i in N:
			a.encode_double(i * 8, float(i) * 1.5)
		var t1 := Time.get_ticks_usec()
		best1 = mini(best1, t1 - t0)

	var best2 := 1 << 30
	for r in REP:
		var t0 := Time.get_ticks_usec()
		for i in N:
			b[i] = float(i) * 1.5
		var t1 := Time.get_ticks_usec()
		best2 = mini(best2, t1 - t0)

	var best3 := 1 << 30
	var acc := 0.0
	for r in REP:
		var t0 := Time.get_ticks_usec()
		for i in N:
			acc += b[i]
		var t1 := Time.get_ticks_usec()
		best3 = mini(best3, t1 - t0)

	print("写 %d 个 double，取 %d 次最小值：" % [N, REP])
	print("  PackedByteArray.encode_double  %8.1f us   (%.1f ns/次)" % [best1, float(best1) * 1000.0 / N])
	print("  PackedFloat64Array 下标写      %8.1f us   (%.1f ns/次)   快 %.2fx" % [best2, float(best2) * 1000.0 / N, float(best1) / maxf(1.0, float(best2))])
	print("  PackedFloat64Array 下标读      %8.1f us   (%.1f ns/次)   快 %.2fx" % [best3, float(best3) * 1000.0 / N, float(best1) / maxf(1.0, float(best3))])
	print("  （校验和 %.1f，防止编译器/引擎优化掉）" % acc)
	quit(0)

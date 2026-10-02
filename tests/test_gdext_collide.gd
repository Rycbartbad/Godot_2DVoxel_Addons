extends SceneTree
## 验证 GDExtension 侧的 collide_batch：
## 1) 与 GDScript 的结果逐位比对  2) 比时间
const Collide := preload("res://src/physics/collide.gd")
const IN_STRIDE := 136
const OUT_STRIDE := 104

func _initialize() -> void:
	if not ClassDB.class_exists("FastPhys"):
		print("FastPhys 不存在 —— 扩展没加载"); quit(1); return
	var fp: Variant = ClassDB.instantiate("FastPhys")
	print("FastPhys 实例 = ", fp)
	print("有 collide_batch 方法? ", fp.has_method("collide_batch"))

	var f := FileAccess.open("res://gdext/collide_pairs.bin", FileAccess.READ)
	var n: int = f.get_32()
	var npts: int = f.get_32()
	var in_f := PackedFloat64Array(); in_f.resize(n * 17)
	var exp_n := PackedFloat64Array(); exp_n.resize(n * 2)
	var exp_c := PackedInt32Array(); exp_c.resize(n)
	var exp_p := PackedFloat64Array(); exp_p.resize(n * 10)
	var obbs: Array = []
	for i in n:
		var a := Collide.OBB.new()
		var b := Collide.OBB.new()
		a.center = Vector2(f.get_double(), f.get_double())
		a.u = Vector2(f.get_double(), f.get_double())
		a.v = Vector2(f.get_double(), f.get_double())
		a.h = Vector2(f.get_double(), f.get_double())
		b.center = Vector2(f.get_double(), f.get_double())
		b.u = Vector2(f.get_double(), f.get_double())
		b.v = Vector2(f.get_double(), f.get_double())
		b.h = Vector2(f.get_double(), f.get_double())
		var mg := f.get_double()
		var o: int = i * 17
		in_f[o + 0] = a.center.x; in_f[o + 1] = a.center.y
		in_f[o + 2] = a.u.x; in_f[o + 3] = a.u.y
		in_f[o + 4] = a.v.x; in_f[o + 5] = a.v.y
		in_f[o + 6] = a.h.x; in_f[o + 7] = a.h.y
		in_f[o + 8] = b.center.x; in_f[o + 9] = b.center.y
		in_f[o + 10] = b.u.x; in_f[o + 11] = b.u.y
		in_f[o + 12] = b.v.x; in_f[o + 13] = b.v.y
		in_f[o + 14] = b.h.x; in_f[o + 15] = b.h.y
		in_f[o + 16] = mg
		exp_n[i * 2] = f.get_double(); exp_n[i * 2 + 1] = f.get_double()
		exp_c[i] = f.get_32()
		f.get_32()
		for k in 10:
			exp_p[i * 10 + k] = f.get_double()
		obbs.append([a, b, mg])
	f.close()

	var input_bytes := in_f.to_byte_array()
	var shape := PackedByteArray(); shape.resize(n * OUT_STRIDE)
	print("输入 %d 字节, 模板 %d 字节, 对数 %d" % [input_bytes.size(), shape.size(), n])
	var t0 := Time.get_ticks_usec()
	var out_bytes: PackedByteArray = fp.collide_batch(input_bytes, shape, n)
	var t1 := Time.get_ticks_usec()
	print("collide_batch 返回 %d 字节, 耗时 %.3f ms" % [out_bytes.size(), float(t1 - t0) / 1000.0])
	if out_bytes.size() != n * OUT_STRIDE:
		print("!! 返回长度不对，期望 %d" % (n * OUT_STRIDE)); quit(1); return

	# 逐位比对
	var bad_n := 0
	var bad_c := 0
	var bad_p := 0
	var shown := 0
	for i in n:
		var base: int = i * OUT_STRIDE
		var nx := out_bytes.decode_double(base + 0)
		var ny := out_bytes.decode_double(base + 8)
		var cnt := out_bytes.decode_s32(base + 16)
		if nx != exp_n[i * 2] or ny != exp_n[i * 2 + 1]:
			bad_n += 1
		if cnt != exp_c[i]:
			bad_c += 1
		for k in 10:
			var got := out_bytes.decode_double(base + 24 + k * 8)
			if got != exp_p[i * 10 + k]:
				bad_p += 1
				break
		if shown < 3 and (cnt != exp_c[i] or nx != exp_n[i * 2]):
			shown += 1
			print("  差异 #%d: gs_count=%d c_count=%d gs_n=(%.17f,%.17f) c_n=(%.17f,%.17f)" % [
				i, exp_c[i], cnt, exp_n[i * 2], exp_n[i * 2 + 1], nx, ny])
	print("=== GDExtension vs GDScript 逐位比对（%d 对）===" % n)
	print("  normal 不一致: %d    count 不一致: %d    接触点不一致: %d" % [bad_n, bad_c, bad_p])

	# 时间对比
	var scratch := Collide.Sat.new()
	var best_g := 1.0e18
	for rep in 5:
		var tg0 := Time.get_ticks_usec()
		for e: Array in obbs:
			Collide.collide(e[0], e[1], e[2], scratch)
		var tg1 := Time.get_ticks_usec()
		best_g = minf(best_g, float(tg1 - tg0))
	var best_c := 1.0e18
	for rep in 9:
		var tc0 := Time.get_ticks_usec()
		var _o: PackedByteArray = fp.collide_batch(input_bytes, shape, n)
		var tc1 := Time.get_ticks_usec()
		best_c = minf(best_c, float(tc1 - tc0))
	print("  GDScript : %.3f ms  (%.0f ns/对)" % [best_g / 1000.0, best_g * 1000.0 / float(n)])
	print("  扩展调用 : %.3f ms  (%.0f ns/对，含调用开销与数组拷贝)" % [best_c / 1000.0, best_c * 1000.0 / float(n)])
	print("  倍数     : %.1fx" % (best_g / best_c))
	quit(0)

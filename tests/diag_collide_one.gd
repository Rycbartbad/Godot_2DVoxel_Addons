extends SceneTree
## 读 collide_pairs.bin 的第 idx 对，把 collide 的全部中间量打出来做对比。
## 注意：GDScript 的 % 不支持 %g，只有 %s/%d/%f/%x —— 用 %.17f。
const Collide := preload("res://src/physics/collide.gd")
const F := "%.17f"

func _v(p: Vector2) -> String:
	return "(" + (F % p.x) + ", " + (F % p.y) + ")"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var idx := 22 if args.is_empty() else int(args[0])
	var f := FileAccess.open("res://gdext/collide_pairs.bin", FileAccess.READ)
	f.seek(8 + idx * 240)
	var oa := Collide.OBB.new()
	var ob := Collide.OBB.new()
	for k in 2:
		var vals: Array = []
		for i in 8:
			vals.append(f.get_double())
		var o: Collide.OBB = oa if k == 0 else ob
		o.center = Vector2(float(vals[0]), float(vals[1]))
		o.u = Vector2(float(vals[2]), float(vals[3]))
		o.v = Vector2(float(vals[4]), float(vals[5]))
		o.h = Vector2(float(vals[6]), float(vals[7]))
	var margin := f.get_double()
	f.close()
	print("a.c=" + _v(oa.center) + " a.u=" + _v(oa.u) + " a.h=" + _v(oa.h))
	print("b.c=" + _v(ob.center) + " b.u=" + _v(ob.u) + " b.h=" + _v(ob.h))
	print("margin=" + (F % margin))
	var s := Collide.Sat.new()
	Collide.sat_signed_into(oa, ob, s)
	print("SAT sep=" + (F % s.sep) + " normal=" + _v(s.normal) + " from_a=" + str(s.from_a))
	var normal := s.normal
	var from_a := s.from_a
	var ref: Collide.OBB = oa if from_a else ob
	var inc: Collide.OBB = ob if from_a else oa
	var ref_normal := normal if from_a else -normal
	var ref_edge := 0
	var best_dot := -INF
	for i in 4:
		var d := ref.edge_normal(i).dot(ref_normal)
		if d > best_dot:
			best_dot = d
			ref_edge = i
	var inc_edge := 0
	var worst_dot := INF
	for i in 4:
		var d2 := inc.edge_normal(i).dot(ref_normal)
		if d2 < worst_dot:
			worst_dot = d2
			inc_edge = i
	var rp1 := ref.edge_start(ref_edge)
	var rp2 := ref.edge_end(ref_edge)
	var ip1 := inc.edge_start(inc_edge)
	var ip2 := inc.edge_end(inc_edge)
	print("ref_edge=" + str(ref_edge) + " best_dot=" + (F % best_dot) + " inc_edge=" + str(inc_edge) + " worst_dot=" + (F % worst_dot))
	print("rp1=" + _v(rp1) + " rp2=" + _v(rp2))
	print("ip1=" + _v(ip1) + " ip2=" + _v(ip2))
	var tangent := (rp2 - rp1).normalized()
	var o1 := -tangent.dot(rp1)
	var o2 := tangent.dot(rp2)
	print("tangent=" + _v(tangent) + " offset1=" + (F % o1) + " offset2=" + (F % o2))
	var seg := Collide._clip_segment(ip1, ip2, -tangent, o1)
	print("裁剪1 -> " + str(seg.size()) + " 点")
	for i in seg.size():
		print("   seg[" + str(i) + "]=" + _v(seg[i]))
	if not seg.is_empty():
		var seg2 := Collide._clip_segment(seg[0], seg[1], tangent, o2)
		print("裁剪2 -> " + str(seg2.size()) + " 点")
		for i in seg2.size():
			print("   seg2[" + str(i) + "]=" + _v(seg2[i]) + " separation=" + (F % (seg2[i] - rp1).dot(ref_normal)))
	quit(0)

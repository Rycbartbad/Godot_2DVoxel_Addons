extends SceneTree
## 随机 OBB 对生成器 —— 覆盖真实场景覆盖不到的形状：
## 任意旋转、深穿透、恰好相切（sep == 0 的边界）、边际内的分离、大小悬殊。
## 输出格式与 dump_collide_bin.gd 完全一致，C++ 侧同一套读取代码。
const Collide := preload("res://src/physics/collide.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var n := 20000 if args.is_empty() else int(args[0])
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260101
	var scratch := Collide.Sat.new()
	var f := FileAccess.open("res://gdext/collide_pairs.bin", FileAccess.WRITE)
	f.store_32(n)
	f.store_32(0)   # 点数稍后回填，这里先占位
	var npts := 0
	var stat := {"none": 0, "spec": 0, "pen": 0, "clip_empty": 0}
	for i in n:
		var oa := Collide.OBB.new()
		var ob := Collide.OBB.new()
		var ra := rng.randf_range(-PI, PI)
		var rb := rng.randf_range(-PI, PI)
		oa.center = Vector2(rng.randf_range(-100.0, 100.0), rng.randf_range(-100.0, 100.0))
		oa.h = Vector2(rng.randf_range(1.0, 12.0), rng.randf_range(1.0, 12.0))
		oa.u = Vector2(cos(ra), sin(ra))
		oa.v = Vector2(-oa.u.y, oa.u.x)
		ob.h = Vector2(rng.randf_range(1.0, 12.0), rng.randf_range(1.0, 12.0))
		ob.u = Vector2(cos(rb), sin(rb))
		ob.v = Vector2(-ob.u.y, ob.u.x)
		# 偏移控制得小一点，让"穿透"和"边际内分离"占多数
		var span := oa.h.x + oa.h.y + ob.h.x + ob.h.y
		ob.center = oa.center + Vector2(rng.randf_range(-span, span), rng.randf_range(-span, span))
		var margin := rng.randf_range(0.0, 3.0)
		var res := Collide.collide(oa, ob, margin, scratch)
		var pts: Array = res["points"]
		var kind := "clip_empty"
		if pts.is_empty():
			kind = "none"
		elif pts.size() == 1 and pts[0]["feature"] == -1:
			kind = "spec"
		else:
			kind = "pen"
		stat[kind] = stat[kind] + 1
		npts += pts.size()
		for o in [oa, ob]:
			f.store_double(o.center.x); f.store_double(o.center.y)
			f.store_double(o.u.x); f.store_double(o.u.y)
			f.store_double(o.v.x); f.store_double(o.v.y)
			f.store_double(o.h.x); f.store_double(o.h.y)
		f.store_double(margin)
		var nrm: Vector2 = res["normal"]
		f.store_double(nrm.x); f.store_double(nrm.y)
		f.store_32(pts.size())
		f.store_32(0)
		for i2 in 2:
			if i2 < pts.size():
				var pd: Dictionary = pts[i2]
				var pos: Vector2 = pd["position"]
				f.store_double(pos.x); f.store_double(pos.y)
				f.store_double(pd["depth"]); f.store_double(pd["sep"]); f.store_double(pd["feature"])
			else:
				for k in 5:
					f.store_double(0.0)
	f.close()
	# 回填点数
	var f2 := FileAccess.open("res://gdext/collide_pairs.bin", FileAccess.READ_WRITE)
	f2.seek(4)
	f2.store_32(npts)
	f2.close()
	print("生成 %d 对（接触点 %d）| 分布: 无接触 %d / 推测 %d / 穿透 %d" % [
		n, npts, stat["none"], stat["spec"], stat["pen"]])
	quit(0)

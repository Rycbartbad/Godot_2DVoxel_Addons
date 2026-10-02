extends SceneTree
## 为什么碎块睡不着？—— 多碎片场景的休眠诊断。
##
## _update_sleep 的规则是：**同岛必须一起睡**，岛的计时取岛内**最小**的 sleep_timer。
## 所以只要一个大岛里有一个还在抖的碎块，整个岛就永远醒着。
## 这里把"到底谁在抖、抖多大、岛有多大"全部打出来，而不是猜。
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

func _scene(n_frag: int, n_boxes: int) -> PWorld:
	var world := PWorld.new()
	world.sleeping_enabled = true
	var g := PBody.new()
	g.position = Vector2(-2000.0, 0.0)
	g.make_static()
	world.add_body(g, [_block(4000, 40)])
	for i in n_boxes:
		var b := PBody.new()
		b.position = Vector2(-300.0 + float(i % 10) * 18.0, -9.0 - float(i / 10) * 18.0)
		world.add_body(b, [_block(16, 16)])
	for i2 in n_frag:
		var f := PBody.new()
		f.position = Vector2(-1200.0 + float(i2 % 60) * 14.0, -300.0 - float(i2 / 60) * 14.0)
		world.add_body(f, [_block(6, 6)])
		f.linear_velocity = Vector2(-60.0 + float(i2 % 11) * 12.0, 40.0)
	return world

func _report(world: PWorld, label: String) -> void:
	var lin_thresh := world.sleep_linear
	var ang_thresh := world.sleep_surface
	var n_awake := 0
	var slow := 0
	var buckets := {}
	var max_lin := 0.0
	var max_ang := 0.0
	var timer_hist := {}
	var stuck: Array = []
	for b: PBody in world.bodies:
		if b.is_static or not b.awake:
			continue
		n_awake += 1
		var v: float = b.linear_velocity.length()
		var w: float = absf(b.angular_velocity)
		max_lin = maxf(max_lin, v)
		max_ang = maxf(max_ang, w)
		if b.is_slow(lin_thresh, ang_thresh):
			slow += 1
		else:
			var surf: float = w * b.bounding_radius()
			# 分清是哪一半卡住的
			var why := "线速度" if v > lin_thresh else "表面速度"
			stuck.append([b.id, v, w, b.position.x, b.position.y, surf, why])
		var k := "%.0f-%.0f" % [floor(v / 2.0) * 2.0, floor(v / 2.0) * 2.0 + 2.0]
		buckets[k] = buckets.get(k, 0) + 1
		var tk := "%.2f" % (floor(b.sleep_timer * 4.0) * 0.25)
		timer_hist[tk] = timer_hist.get(tk, 0) + 1
	print("\n--- %s ---" % label)
	print("  清醒 %d | 其中「慢」（低于阈值）%d | 最快的那个 %.1f px/s | 最大角速度 %.3f rad/s" % [
		n_awake, slow, max_lin, max_ang])
	# 岛结构
	var islands := world._build_islands()
	var sizes: Array = []
	for isle: Dictionary in islands:
		sizes.append((isle["manifolds"] as Array).size())
	sizes.sort()
	sizes.reverse()
	var top := []
	for i in mini(6, sizes.size()):
		top.append(sizes[i])
	print("  岛 %d 个 | 最大几个岛的流形数: %s" % [islands.size(), str(top)])
	var parts: Array = []
	for k2 in buckets:
		parts.append("%s:%d" % [k2, buckets[k2]])
	parts.sort()
	print("  速度直方图(px/s): ", " ".join(parts))
	var tparts: Array = []
	for k3 in timer_hist:
		tparts.append("%s:%d" % [k3, timer_hist[k3]])
	tparts.sort()
	print("  sleep_timer 直方图(s): ", " ".join(tparts))
	stuck.sort_custom(func(x, y): return x[1] > y[1])
	var by_lin := 0
	var by_surf := 0
	for s in stuck:
		if s[6] == "线速度":
			by_lin += 1
		else:
			by_surf += 1
	print("  不达标的 %d 个里：线速度超标 %d 个，表面速度超标 %d 个" % [stuck.size(), by_lin, by_surf])
	print("  最吵的 8 个:")
	for i in mini(8, stuck.size()):
		var s2: Array = stuck[i]
		print("     id=%-4d |v|=%7.2f |w|=%6.3f 表面=%6.2f  <- %s  在 (%.1f, %.1f)" % [
			s2[0], s2[1], s2[2], s2[5], s2[6], s2[3], s2[4]])

func _initialize() -> void:
	print("=== 多碎片休眠诊断（阈值: 线速度 %.1f px/s, 表面速度 %.1f px/s, 持续 %.2f s）===" % [
		6.0, 6.0, 0.4])
	var w := _scene(300, 40)
	for i in 400:
		w.step(1.0 / 60.0)
	_report(w, "落定 400 步之后")
	for i in 600:
		w.step(1.0 / 60.0)
	_report(w, "再跑 600 步（总共 1000 步 ≈ 16.7 秒）")
	quit(0)

extends SceneTree
## 融合后的每帧成本拆分：物理 / 渲染同步 / 其它。
##
## 重点看 PixelWorld._physics_process 里那段
##     renderer.prune(_live_ids()); for b in world.bodies: renderer.sync(b)
## —— 它是 O(n) 且每帧都跑，融合后门面不再重复做，但节点这边值得量。
const AddonWorld := preload("res://src/nodes/pixel_world.gd")
const AddonBody := preload("res://src/nodes/pixel_body_2d.gd")
const AddonShape := preload("res://src/nodes/pixel_shape_2d.gd")

func _make(nbox: int) -> Node2D:
	var pw = AddonWorld.new()
	var g = AddonBody.new(); g.position = Vector2(0, 220); g.is_static = true
	pw.add_child(g)
	var gs = AddonShape.new(); gs.rect_size = Vector2i(768, 100); g.add_child(gs)
	for i in nbox:
		var b = AddonBody.new()
		b.position = Vector2(20 + (i % 40) * 18, 20 - (i / 40) * 18)
		pw.add_child(b)
		var s = AddonShape.new(); s.rect_size = Vector2i(16, 16); s.material_id = 2
		b.add_child(s)
	get_root().add_child(pw)
	return pw

func _bench(nbox: int) -> void:
	var pw = _make(nbox)
	await process_frame
	await process_frame
	pw.rebuild()
	var n: int = pw.world.bodies.size()
	# 落定一下，避免测的全是"刚出生"的状态
	for i in 60:
		pw.world.step(1.0 / 60.0)

	var STEPS := 300
	var t0 := Time.get_ticks_usec()
	for i in STEPS:
		pw.world.step(1.0 / 60.0)
	var phys := (Time.get_ticks_usec() - t0) / float(STEPS)

	# 渲染同步那一段（与 _physics_process 里逐字相同）
	var t1 := Time.get_ticks_usec()
	for i in STEPS:
		pw.renderer.prune(pw._live_ids())
	var pr := (Time.get_ticks_usec() - t1) / float(STEPS)
	var t1b := Time.get_ticks_usec()
	for i in STEPS:
		for b in pw.world.bodies:
			if not b.is_static:          # 与节点 _physics_process 的新行为一致
				pw.renderer.sync(b)
	var rnd := (Time.get_ticks_usec() - t1b) / float(STEPS) + pr
	# 对照：旧行为（静态体也每帧同步）
	var t1c := Time.get_ticks_usec()
	for i in STEPS:
		for b in pw.world.bodies:
			pw.renderer.sync(b)
	var old := (Time.get_ticks_usec() - t1c) / float(STEPS) + pr

	var t2 := Time.get_ticks_usec()
	for i in STEPS:
		pw._live_ids()
	var live := (Time.get_ticks_usec() - t2) / float(STEPS)

	print("刚体 %4d | 物理 %7.3f | prune %6.3f | sync(新) %7.3f | sync(旧) %7.3f | 省 %5.1f%% | 新合计 %7.3f us" % [
		n, phys, pr, rnd - pr, old - pr, (1.0 - rnd / maxf(old, 0.001)) * 100.0, phys + rnd])
	pw.queue_free()
	await process_frame

func _initialize() -> void:
	print("=== 融合后的每帧成本拆分 ===")
	print("（每项 = 300 次的平均，单位微秒）")
	for n in [4, 60, 240, 600]:
		await _bench(n)
	quit(0)

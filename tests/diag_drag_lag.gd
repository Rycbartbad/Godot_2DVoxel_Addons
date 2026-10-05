extends SceneTree
## 定位"没接触到别的物体也很卡"（拖动时）：
##   (a) demo 规则每帧的**固定**开销（by_id 建表 + contact_pair_count），接触为 0 时也在花
##   (b) 抓取对物理步进的代价（对照：不抓）—— 看早先那个"抓取时限制子步"的修复还在不在
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _box(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _scene(n: int) -> PWorld:
	var w := PWorld.new()
	w.gravity = Vector2(0, 600)
	var g := PBody.new()
	g.position = Vector2(0, 400)
	g.make_static()
	w.add_body(g, [_box(2000, 40)], Callable(), true)
	for i in n:
		var b := PBody.new()
		b.position = Vector2((i % 20) * 60 - 600, -100 - (i / 20) * 60)
		w.add_body(b, [_box(40, 40)], Callable(), true)
	return w

func _initialize() -> void:
	# (a) demo 规则的固定开销
	var w := _scene(100)
	for i in 30:
		w.step(1.0 / 60.0)
	var t := Time.get_ticks_usec()
	var by_id := {}
	for b in w.bodies:
		by_id[b.id] = b
	var ta := (Time.get_ticks_usec() - t) / 1000.0
	t = Time.get_ticks_usec()
	var n := w.contact_pair_count()
	var tb := (Time.get_ticks_usec() - t) / 1000.0
	print("(a) 刚体 %d 个：by_id 建表 %.4f ms，contact_pair_count %.4f ms（接触 %d 对）" % [
		w.bodies.size(), ta, tb, n])

	# (b) 抓取 vs 不抓：物理步进的代价
	var w2 := _scene(100)
	for i in 30:
		w2.step(1.0 / 60.0)
	var t0 := Time.get_ticks_usec()
	for i in 120:
		w2.step(1.0 / 60.0)
	var no_grab := (Time.get_ticks_usec() - t0) / 1000.0
	var target: PBody = w2.bodies[1]
	print("(b) 不抓：120 步 %.1f ms（%.3f ms/帧）" % [no_grab, no_grab / 120.0])
	# 开始抓
	w2.grab_at(target.position)          # 名字猜的，若不存在会在下面报错
	var t1 := Time.get_ticks_usec()
	for i in 120:
		w2.set_grab_target(target.position + Vector2(sin(i * 0.3) * 40, 0))
		w2.step(1.0 / 60.0)
	var grabbed := (Time.get_ticks_usec() - t1) / 1000.0
	print("(b) 抓着：120 步 %.1f ms（%.3f ms/帧）-> 抓取让它慢 %.1f 倍" % [
		grabbed, grabbed / 120.0, grabbed / maxf(no_grab, 0.001)])
	print("    is_grabbing = %s" % str(w2.is_grabbing()))
	quit(0)

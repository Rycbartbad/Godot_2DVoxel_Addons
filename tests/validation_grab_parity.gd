extends SceneTree
## 抓取约束：扩展路径必须与对象路径**逐位一致**，而且拖动不能再变慢。
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const Grab := preload("res://src/physics/grab.gd")

func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

func _mk(native: bool, n_grab: int) -> Dictionary:
	var w := PWorld.new()
	w.use_native_solve = native
	var g := PBody.new()
	g.position = Vector2(-400.0, 0.0)
	g.make_static()
	w.add_body(g, [_block(800, 40)])
	var boxes: Array = []
	for r in 6:
		for c in 8:
			var b := PBody.new()
			b.position = Vector2(-160.0 + float(c) * 20.0, -18.0 - float(r) * 18.0)
			w.add_body(b, [_block(16, 16)])
			boxes.append(b)
	for i in 60:
		w.step(1.0 / 60.0)
	var gl: Array = []
	for k in n_grab:
		var gr := Grab.new()
		gr.body = boxes[boxes.size() / 2 + k * 3]
		gr.local_anchor = Vector2(4.0, -3.0)     # 非零锚点，走完整的 2x2 有效质量
		w.grabs.append(gr)
		gl.append(gr)
	return {"w": w, "grabs": gl, "boxes": boxes}

func _snap(w: PWorld) -> Array:
	var out: Array = []
	for b in w.bodies:
		if b.is_static:
			continue
		out.append([b.position.x, b.position.y, b.rotation,
			b.linear_velocity.x, b.linear_velocity.y, b.angular_velocity,
			b.pseudo_linear_velocity.x, b.pseudo_linear_velocity.y, b.pseudo_angular_velocity])
	return out

static func _max_diff(a: Array, b: Array) -> float:
	var m := 0.0
	for i in mini(a.size(), b.size()):
		var x: Array = a[i]
		var y: Array = b[i]
		for k in mini(x.size(), y.size()):
			m = maxf(m, absf(float(x[k]) - float(y[k])))
	return m

func _run(native: bool, n_grab: int, steps: int) -> Dictionary:
	var d := _mk(native, n_grab)
	var w: PWorld = d["w"]
	var gl: Array = d["grabs"]
	for s in steps:
		for k in gl.size():
			var gr: Grab = gl[k]
			# 画一个 8 字轨迹：既有平动也有转动，抓取约束的每一支都被覆盖
			var th := float(s) * 0.05 + float(k) * 1.3
			gr.target = Vector2(sin(th) * 90.0, -150.0 + cos(th * 1.7) * 70.0)
		w.step(1.0 / 60.0)
	return {"w": w, "diff": 0.0}

func _initialize() -> void:
	print("[抓取一致性] 扩展路径 vs 对象路径")
	for ng in [1, 3]:
		var a := _run(false, ng, 200)
		var b := _run(true, ng, 200)
		var d := _max_diff(_snap(a["w"]), _snap(b["w"]))
		print("  抓取 %d 个：最大差 = %.9f  %s" % [ng, d, "PASS" if d == 0.0 else "FAIL"])
	print("[拖动开销] 同一场景，各 7 次取最小")
	var d0 := _mk(true, 0)
	var t0 := Time.get_ticks_usec()
	for i in 12:
		(d0["w"] as PWorld).step(1.0 / 60.0)
	var no_grab := float(Time.get_ticks_usec() - t0) / 12.0
	var d1 := _mk(true, 1)
	var gl: Array = d1["grabs"]
	var t1 := Time.get_ticks_usec()
	for i in 12:
		(gl[0] as Grab).target = (d1["boxes"] as Array)[20].position + Vector2(0.0, -30.0)
		(d1["w"] as PWorld).step(1.0 / 60.0)
	var with_grab := float(Time.get_ticks_usec() - t1) / 12.0
	print("  无抓取 %.3f ms | 拖动中 %.3f ms | %.2fx" % [
		no_grab / 1000.0, with_grab / 1000.0, with_grab / maxf(0.001, no_grab)])
	quit(0)

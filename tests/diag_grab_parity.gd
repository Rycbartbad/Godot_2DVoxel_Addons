extends SceneTree
## 48 箱堆 + 1 个抓取：定位首次分歧（哪个物体、哪个字段）
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

func _mk(native: bool, sleeping: bool) -> Dictionary:
	var w := PWorld.new()
	w.use_native_solve = native
	w.sleeping_enabled = sleeping
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
	var gr := Grab.new()
	gr.body = boxes[24]
	gr.local_anchor = Vector2(4.0, -3.0)
	w.grabs.append(gr)
	return {"w": w, "g": gr, "boxes": boxes}

func _snap(w: PWorld) -> Array:
	var out: Array = []
	for b in w.bodies:
		out.append([b.position.x, b.position.y, b.rotation, b.linear_velocity.x, b.linear_velocity.y,
			b.angular_velocity, 1.0 if b.awake else 0.0])
	return out

func _initialize() -> void:
	for sleeping in [true, false]:
		print("=== sleeping=%s ===" % str(sleeping))
		var A := _mk(false, sleeping)
		var B := _mk(true, sleeping)
		var first := -1
		for s in 120:
			(A["g"] as Grab).target = Vector2(0.0, -150.0)
			(B["g"] as Grab).target = Vector2(0.0, -150.0)
			(A["w"] as PWorld).step(1.0 / 60.0)
			(B["w"] as PWorld).step(1.0 / 60.0)
			var sa := _snap(A["w"])
			var sb := _snap(B["w"])
			var worst := 0.0
			var who := -1
			var fld := -1
			for i in mini(sa.size(), sb.size()):
				for k in 7:
					var d: float = absf(float(sa[i][k]) - float(sb[i][k]))
					if d > worst:
						worst = d
						who = i
						fld = k
			if worst > 0.0 and first < 0:
				first = s
				print("  首次分歧 步%d 体%d 字段%d 差=%.9f" % [s, who, fld, worst])
				print("    对象 %s" % str(sa[who]))
				print("    扩展 %s" % str(sb[who]))
		print("  首次分歧步=%d" % first)
	quit(0)

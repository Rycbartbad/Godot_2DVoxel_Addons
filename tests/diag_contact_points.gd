extends SceneTree
## 临时探针（用完即删）：op 35（**全部**接触点 + **各自**冲量）的验证。
## 场景：一个方块**平放**落在静态地面上 —— 面-面接触，期望 **2 个**接触点，
## 且各点冲量之和 ≈ 整对的总冲量（旧接口只给一个代表点 + 总冲量）。
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _box(w: int, h: int, mat: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), mat)
	return s

func _call(rp, idx: int, cap: int) -> PackedByteArray:
	var ops := PackedByteArray()
	ops.resize(9)
	ops.encode_u8(0, 35)
	ops.encode_u32(1, idx)
	ops.encode_s32(5, cap)
	var tmpl := PackedByteArray()
	tmpl.resize(4 + (4 + cap * 6) * 8)
	return rp.cmd(ops, tmpl)

func _initialize() -> void:
	var w := PWorld.new()
	var ground := PBody.new()
	ground.position = Vector2(0, 100)
	ground.make_static()
	w.add_body(ground, [_box(200, 8, 1)], Callable(), true)
	var box := PBody.new()
	box.position = Vector2(50, 84)
	w.add_body(box, [_box(32, 8, 2)], Callable(), true)
	# ⚠️ 必须在**撞击过程中**采样：方块落定后会睡着，而休眠接触
	#    has_any_active_contact() 是 false —— 那时接触对数是 0（第一版就踩了这个）。
	# ⚠️ 必须先 _rp_ensure()：扩展是**懒实例化**的，直接读 _rp 会拿到 null，
	#    而报错是 "Nonexistent function 'cmd' in base 'Nil'" —— 指不到真因。
	#    （pworld.gd:735 的墓碑注释里记着同一个坑。）
	w._rp_ensure()
	var rp = w._rp
	var n_pairs := 0
	var hit_frame := -1
	for i in 60:
		w.step(1.0 / 60.0)
		n_pairs = _call(rp, 0, 0).decode_s32(0)
		if n_pairs > 0 and hit_frame < 0:
			hit_frame = i
	print("第一次出现接触对：第 %d 帧；本次采样接触对数量 = %d" % [hit_frame, n_pairs])
	for idx in n_pairs:
		var head := _call(rp, idx, 0)
		var n := head.decode_s32(0)
		print("对 %d：点数 = %d（旧接口只会给 1 个）" % [idx, n])
		if n <= 0:
			continue
		var full := _call(rp, idx, 4 + n * 6)
		var ida := int(full.decode_double(4))
		var idb := int(full.decode_double(12))
		var total := full.decode_double(28)
		print("  id_a=%d id_b=%d 总冲量=%.4f" % [ida, idb, total])
		var s := 0.0
		for i in n:
			var o := 32 + i * 48
			var nx := full.decode_double(o)
			var ny := full.decode_double(o + 8)
			var px := full.decode_double(o + 16)
			var py := full.decode_double(o + 24)
			var d := full.decode_double(o + 32)
			var imp := full.decode_double(o + 40)
			s += absf(imp)
			print("   点%d 法向=(%.2f,%.2f) 位置=(%.2f,%.2f) 距离=%.3f 冲量=%.4f" % [i, nx, ny, px, py, d, imp])
		print("  各点冲量绝对值之和 = %.4f（总冲量 %.4f，比值 %.3f）" % [s, total, s / maxf(total, 1e-9)])
	quit(0)

extends SceneTree
## GPU 破坏内核验证：与 CPU 路径逐步对比，并测量加速比。
## 需要 Forward+/Vulkan（gl_compatibility / headless 下 GPU 不可用，测试会自动跳过）。

const Bits := preload("res://src/core/pixel_bits.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const PixelChunk := preload("res://src/core/pixel_chunk.gd")
const Destruction := preload("res://src/core/destruction.gd")

var _pass := 0
var _fail := 0

func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
		print("  PASS  ", name, "  ", detail)
	else:
		_fail += 1
		print("  FAIL  ", name, "  ", detail)

func _block(w: int, h: int, mat: int = 1) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, mat)
	return s

func _wave(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			if y > 8 and y < h - 8:
				s.set_pixel(x, y, 1)
			elif (x / 6) % 2 == 0:
				s.set_pixel(x, y, 1)
	return s

## 把 Shape 规范化成可比较的像素签名
func _signature(shape: PixelShape) -> String:
	var list: Array = []
	for k: int in shape.chunks:
		var c: PixelChunk = shape.chunks[k]
		var bx := PixelShape.key_x(k) << 3
		var by := PixelShape.key_y(k) << 3
		var bits: int = c.occ
		while bits != 0:
			var i := Bits.first_bit_index(bits)
			bits &= bits - 1
			list.append(Vector2i(bx + (i & 7), by + (i >> 3)))
	list.sort_custom(func(p: Vector2i, q: Vector2i) -> bool:
		return p.y < q.y or (p.y == q.y and p.x < q.x))
	return str(list)

func _parts_signature(parts: Array) -> String:
	var sigs: Array = []
	for p: PixelShape in parts:
		sigs.append(_signature(p))
	sigs.sort()
	return " | ".join(sigs)

func _initialize() -> void:
	print("=== GPU 破坏内核验证 ===")
	var gpu = Destruction.gpu_backend()
	if gpu == null or not gpu.available:
		print("  SKIP: GPU 不可用 (", "null" if gpu == null else gpu.last_error, ")")
		print("  请用 Forward+/Vulkan 运行：--rendering-driver vulkan")
		quit(2)
		return
	print("  GPU: ", RenderingServer.get_video_adapter_name(), " | 阈值 = ", 24, " chunks")

	_compare("64x64 圆形爆炸", func() -> PixelShape: return _block(64, 64),
		Destruction.Damage.circle(Vector2(32.0, 32.0), 10.0))
	_compare("64x64 竖直切断", func() -> PixelShape: return _block(64, 64),
		Destruction.Damage.segment(Vector2(32.0, -4.0), Vector2(32.0, 68.0), 2.0))
	_compare("64x64 对角切断", func() -> PixelShape: return _block(64, 64),
		Destruction.Damage.segment(Vector2(-4.0, 0.0), Vector2(68.0, 64.0), 2.0))
	_compare("128x128 十字切断", func() -> PixelShape: return _block(128, 128),
		Destruction.Damage.segment(Vector2(64.0, -4.0), Vector2(64.0, 132.0), 3.0))
	_compare("波形凹形 + 爆炸", func() -> PixelShape: return _wave(128, 96),
		Destruction.Damage.circle(Vector2(40.0, 48.0), 14.0))
	_compare("矩形挖洞", func() -> PixelShape: return _block(96, 96),
		Destruction.Damage.rect(Vector2(48.0, 48.0), Vector2(16.0, 6.0)))
	_bench()

	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _compare(label: String, factory: Callable, damage) -> void:
	# --- CPU ---
	var s_cpu: PixelShape = factory.call()
	Destruction.apply_damage(s_cpu, damage)
	var parts_cpu := Destruction.split(s_cpu, 1)

	# --- GPU ---
	var s_gpu: PixelShape = factory.call()
	var accel: Dictionary = Destruction.apply_damage_and_split_gpu(s_gpu, damage, 1, true)
	if accel.is_empty():
		_check(label, false, "GPU 路径未启用（规模不足或溢出）")
		return
	var parts_gpu: Array = accel["parts"]

	var occ_same := _signature(s_cpu) == _signature(s_gpu)
	var parts_same := _parts_signature(parts_cpu) == _parts_signature(parts_gpu)
	_check(label + " / 残留占用一致", occ_same,
		"" if occ_same else "cpu=%d px gpu=%d px" % [s_cpu.pixel_count(), s_gpu.pixel_count()])
	_check(label + " / 分片结果一致", parts_same,
		"cpu=%d 片 gpu=%d 片" % [parts_cpu.size(), parts_gpu.size()])


func _bench() -> void:
	print("\n[性能对比]")
	# 形状在计时之外预先建好，只测"破坏 + 分片"本身
	for cfg in [[64, 64, 8.0], [128, 128, 14.0], [192, 192, 20.0]]:
		var w: int = cfg[0]
		var h: int = cfg[1]
		var r: float = cfg[2]
		var dmg := Destruction.Damage.circle(Vector2(w * 0.5, h * 0.5), r)
		var reps := 5

		var cpu_shapes: Array = []
		var gpu_shapes: Array = []
		for i in reps:
			cpu_shapes.append(_block(w, h))
			gpu_shapes.append(_block(w, h))

		var t0 := Time.get_ticks_usec()
		for i in reps:
			var s: PixelShape = cpu_shapes[i]
			Destruction.apply_damage(s, dmg)
			Destruction.split(s, 1)
		var cpu_us := (Time.get_ticks_usec() - t0) / float(reps)

		var t1 := Time.get_ticks_usec()
		for i in reps:
			Destruction.apply_damage_and_split_gpu(gpu_shapes[i], dmg, 1)
		var gpu_us := (Time.get_ticks_usec() - t1) / float(reps)

		var chunks := int(ceil(w / 8.0)) * int(ceil(h / 8.0))
		var back = Destruction.gpu_backend()
		print("  %3dx%-3d (%4d chunks): CPU %7.3f ms | GPU %7.3f ms | 加速 %.1fx   [提交 %.2f / 回读 %.2f / 拆包 %.2f]" % [
			w, h, chunks, cpu_us / 1000.0, gpu_us / 1000.0, cpu_us / maxf(1.0, gpu_us),
			back.last_submit_usec / 1000.0, back.last_readback_usec / 1000.0, back.last_unpack_usec / 1000.0])

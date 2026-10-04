extends SceneTree
## 临时探针：op 35 验证失败（0 接触）的**真因** —— 逐帧看方块到底动没动。
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
	w.gravity = Vector2(0, 600)
	var ground := PBody.new()
	ground.position = Vector2(0, 100)
	ground.make_static()
	w.add_body(ground, [_box(200, 8, 1)], Callable(), true)
	var box := PBody.new()
	box.position = Vector2(50, 84)
	w.add_body(box, [_box(32, 8, 2)], Callable(), true)
	w._rp_ensure()
	var rp = w._rp
	print("地面 aabb=%s rects=%d static=%s" % [str(ground.aabb), ground.rects.size(), str(ground.is_static)])
	print("方块 aabb=%s rects=%d static=%s awake=%s mass=%.3f" % [str(box.aabb), box.rects.size(), str(box.is_static), str(box.awake), box.mass])
	print("世界刚体数=%d 重力=%s" % [w.bodies.size(), str(w.gravity)])
	for i in 90:
		w.step(1.0 / 60.0)
		var n := _call(rp, 0, 0).decode_s32(0)
		if i < 4 or i % 15 == 0 or (n > 0 and i < 60):
			print("帧%2d 方块 y=%.3f vy=%.3f awake=%s aabb=%s 接触对=%d" % [i, box.position.y, box.linear_velocity.y, str(box.awake), str(box.aabb), n])
	quit(0)

extends SceneTree
## Rapier 包装层的验证：GDScript -> RapierPhys.cmd() -> rapier_bridge.dll -> Rapier
##
## 这一层只是**薄包装**（命令流 in / 结果流 out），存在的意义是让 Godot 侧能调 Rapier。
## 这里跑本项目的两个关键场景，看数据对不对：
##   A 幽灵碰撞：滑过 60 段拼接地面（Rapier #669 判据）
##   B 角接触：40° 的 24x24 方块必须倒
##
## 命令流格式见 gdext/fastphys.cpp 顶部注释。

const OP_RESET := 0
const OP_SET_GRAVITY := 1
const OP_STEP := 2
const OP_BODY_NEW := 3
const OP_SET_RECTS := 5
const OP_SET_VEL := 7
const OP_GET_STATE := 8
const OP_IS_SLEEPING := 9
const OP_CONTACT_COUNT := 11
const OP_BODY_COUNT := 13

var _pass := 0
var _fail := 0

func _c(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
		print("  PASS  ", name, "  ", detail)
	else:
		_fail += 1
		print("  FAIL  ", name, "  ", detail)

# ---- 小端写入（PackedByteArray 必须自己 resize，encode_* 不会自动扩容）----
func _u8(b: PackedByteArray, v: int) -> void:
	b.resize(b.size() + 1)
	b.encode_u8(b.size() - 1, v)

func _i32(b: PackedByteArray, v: int) -> void:
	var n := b.size()
	b.resize(n + 4)
	b.encode_s32(n, v)

func _f64(b: PackedByteArray, v: float) -> void:
	var n := b.size()
	b.resize(n + 8)
	b.encode_double(n, v)

func _f32(b: PackedByteArray, v: float) -> void:
	var n := b.size()
	b.resize(n + 4)
	b.encode_float(n, v)

## 一趟发送：返回 (written, 结果字节)
func _send(inst: Object, cmds: PackedByteArray, out_cap: int) -> Array:
	var inp := PackedByteArray()
	_i32(inp, out_cap)
	_i32(inp, cmds.size())
	inp.append_array(cmds)
	var tmpl := PackedByteArray()
	tmpl.resize(4 + out_cap)
	var res: PackedByteArray = inst.cmd(inp, tmpl)
	if res.size() < 4:
		return [0, PackedByteArray()]
	return [res.decode_s32(0), res]

func _block_rects(w: int, h: int, x0: float = 0.0, y0: float = 0.0) -> PackedByteArray:
	var r := PackedByteArray()
	_f32(r, x0); _f32(r, y0); _f32(r, float(w)); _f32(r, float(h))
	return r

func _initialize() -> void:
	print("=== Rapier 包装层验证 ===")
	if not ClassDB.class_exists("RapierPhys"):
		print("  FAIL  找不到 RapierPhys 类（扩展没加载？）")
		quit(1)
		return
	var inst: Object = ClassDB.instantiate("RapierPhys")
	_c("拿到 RapierPhys 实例", inst != null)
	if inst == null:
		quit(1)
		return

	# ---- A 幽灵碰撞：60 段拼接地面 ----
	var SEG := 20.0
	var SEGS := 60
	var BOX := 16.0
	var SPEED := 120.0
	var cmds := PackedByteArray()
	_u8(cmds, OP_RESET)
	_u8(cmds, OP_SET_GRAVITY); _f64(cmds, 0.0); _f64(cmds, 600.0)
	_u8(cmds, OP_BODY_NEW); _i32(cmds, 1); _f64(cmds, 0.0); _f64(cmds, 0.0); _f64(cmds, 0.0)
	var gid := 1
	# ⚠️ body_set_rects 是**替换**语义（先清空旧碰撞体），所以 N 段必须一次发完。
	#    分 N 次调用只会留下最后一段 —— 第一版就是这么错的（方块掉出世界 3822 px）。
	var all := PackedByteArray()
	for i in SEGS:
		all.append_array(_block_rects(20, 40, float(i) * SEG, 0.0))
	_u8(cmds, OP_SET_RECTS); _i32(cmds, gid); _i32(cmds, SEGS)
	cmds.append_array(all)
	_f64(cmds, 0.5)
	_u8(cmds, OP_BODY_NEW); _i32(cmds, 0); _f64(cmds, 10.0); _f64(cmds, -BOX); _f64(cmds, 0.0)
	var bid := 2
	_u8(cmds, OP_SET_RECTS); _i32(cmds, bid); _i32(cmds, 1)
	cmds.append_array(_block_rects(16, 16))
	_f64(cmds, 0.5)
	var r0 := _send(inst, cmds, 64)
	_c("命令流执行成功（reset/建地面/建方块）", r0[0] >= 8, "written=%d" % r0[0])

	# 落定
	for i in 60:
		var s := PackedByteArray()
		_u8(s, OP_STEP); _f64(s, 1.0 / 60.0)
		_send(inst, s, 8)
	var st := _send(inst, _cmd_get_state(bid), 64)
	var rest_y: float = st[1].decode_double(4 + 8)     # 结果段第 2 个 f64 = y
	# 驱动 600 步
	var prev_x: float = st[1].decode_double(4)
	var start_x := prev_x
	var backwards := 0
	var max_dy := 0.0
	for i in 600:
		var vy := 0.0
		var cur := _send(inst, _cmd_get_state(bid), 64)
		vy = cur[1].decode_double(4 + 32)        # 第 5 个 f64 = vy
		var s := PackedByteArray()
		_u8(s, OP_SET_VEL); _i32(s, bid); _f64(s, SPEED); _f64(s, vy); _f64(s, 0.0)
		_u8(s, OP_STEP); _f64(s, 1.0 / 60.0)
		_send(inst, s, 8)
		var n := _send(inst, _cmd_get_state(bid), 64)
		var x: float = n[1].decode_double(4)
		var y: float = n[1].decode_double(4 + 8)
		if x - prev_x < -1.0e-4:
			backwards += 1
		max_dy = maxf(max_dy, absf(y - rest_y))
		prev_x = x
	var traveled: float = prev_x - start_x
	var expected := SPEED / 60.0 * 600.0
	var err := absf(traveled - expected) / expected * 100.0
	_c("A 拼接地面滑行（Rapier #669 判据）", backwards == 0 and max_dy < 1.0 and err < 5.0,
		"前进 %.2f / 期望 %.2f (误差 %.2f%%) | 倒退 %d 次 | 最大偏离 %.4f px" % [
			traveled, expected, err, backwards, max_dy])

	# ---- B 角接触：40° 的 24x24 方块 ----
	var inst2: Object = ClassDB.instantiate("RapierPhys")
	var th := deg_to_rad(40.0)
	var low := 12.0 * (sin(th) + cos(th))
	var c2 := PackedByteArray()
	_u8(c2, OP_RESET)
	_u8(c2, OP_SET_GRAVITY); _f64(c2, 0.0); _f64(c2, 600.0)
	_u8(c2, OP_BODY_NEW); _i32(c2, 1); _f64(c2, 0.0); _f64(c2, 0.0); _f64(c2, 0.0)
	_u8(c2, OP_SET_RECTS); _i32(c2, 1); _i32(c2, 1)
	c2.append_array(_block_rects(4000, 40, -2000.0, 0.0))
	_f64(c2, 0.5)
	_u8(c2, OP_BODY_NEW); _i32(c2, 0); _f64(c2, 0.0); _f64(c2, -low); _f64(c2, th)
	# 矩形居中在刚体原点上：[-12,-12,24,24]，这样原点就是方块中心
	_u8(c2, OP_SET_RECTS); _i32(c2, 2); _i32(c2, 1)
	c2.append_array(_block_rects(24, 24, -12.0, -12.0))
	_f64(c2, 0.5)
	_send(inst2, c2, 64)
	for i in 120:
		var s2 := PackedByteArray()
		_u8(s2, OP_STEP); _f64(s2, 1.0 / 60.0)
		_send(inst2, s2, 8)
	var fin := _send(inst2, _cmd_get_state(2), 64)
	var rot_deg: float = rad_to_deg(fin[1].decode_double(4 + 16))
	_c("B 角接触 40° 方块会倒", absf(rot_deg - 40.0) > 20.0,
		"终态 %.3f°（转了 %.3f°）" % [rot_deg, rot_deg - 40.0])

	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func _cmd_get_state(id: int) -> PackedByteArray:
	var b := PackedByteArray()
	_u8(b, OP_GET_STATE)
	_i32(b, id)
	return b

extends SceneTree
## 接触导出接口的**正确**测量：op 11（接触对计数）/ op 35（全部点+各自冲量）。
## ⚠️ 它最早还测过 op 12（旧：一个代表点+总冲量），那个接口**已删除**（静默返回全 0）。
##
## ⚠️⚠️ 协议（照 pworld.gd:645 的 _rp_send 抄，别再手搓）：
##   inp = i32 out_cap + i32 cmds.size() + 命令流      <- **8 字节头不能省**
##   tmpl = 4 + out_cap 字节
##   res[0..4) = **实际写入字节数**（不是数据！），数据从**偏移 4** 开始
## 我前面两版探针把这两条都做错了：漏了头 -> "未知操作码 247（命令流错位）"；
## 把 res 的头 4 字节当数据读 -> "数量 = 0" 其实是"写入 0 字节"。
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _box(w: int, h: int, mat: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), mat)
	return s

func _send(rp, cmds: PackedByteArray, out_cap: int) -> PackedByteArray:
	var inp := PackedByteArray()
	inp.resize(8)
	inp.encode_s32(0, out_cap)
	inp.encode_s32(4, cmds.size())
	inp.append_array(cmds)
	var tmpl := PackedByteArray()
	tmpl.resize(4 + out_cap)
	return rp.cmd(inp, tmpl)

func _u8(v: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(1)
	b.encode_u8(0, v)
	return b

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
	var best := 0
	var best_frame := -1
	for i in 90:
		w.step(1.0 / 60.0)
		var r := _send(rp, _u8(11), 4)
		var n: int = r.decode_s32(4) if r.decode_s32(0) >= 4 else -1
		if n > best:
			best = n
			best_frame = i
	print("op 11 接触对计数：全程最大 %d（第 %d 帧）" % [best, best_frame])
	if best <= 0:
		quit(0)
		return
	# ⚠️ op 12（旧接口：一个代表点 + 整对总冲量）**已删除** —— 它在本项目里静默返回全 0，
	#    而且"整个面的冲量附在一个代表点上"正是要修的缺陷。这里不再测它。
	#    （本探针最早的那一版测过它，输出全是 0，那份记录在提交信息里。）
	# 新接口：全部点 + 各自冲量
	var c35 := PackedByteArray()
	c35.resize(9)
	c35.encode_u8(0, 35)
	c35.encode_u32(1, 0)
	c35.encode_s32(5, 0)
	var r35 := _send(rp, c35, 4)
	var np: int = r35.decode_s32(4)
	print("op 35（新）：点数 = %d（旧接口只会给 1 个）" % np)
	if np > 0:
		var c35b := PackedByteArray()
		c35b.resize(9)
		c35b.encode_u8(0, 35)
		c35b.encode_u32(1, 0)
		c35b.encode_s32(5, 4 + np * 6)
		var rf := _send(rp, c35b, 4 + (4 + np * 6) * 8)
		var total := rf.decode_double(32)
		var s := 0.0
		# ⚠️ payload 从 res 的**偏移 4** 开始（前 4 字节是"实际写入字节数"），
		#    所以 [i32 n][id_a][id_b][n_points][total] 之后，第 i 个点从 40 + i*48 起。
		#    写成 36 会整体错 4 字节 —— 位置/距离/冲量全读成 0（我第一版就是这样）。
		for i in np:
			var o := 40 + i * 48
			s += absf(rf.decode_double(o + 40))
			print("  点%d 位置=(%.2f,%.2f) dist=%.3f 冲量=%.4f" % [i, rf.decode_double(o + 16), rf.decode_double(o + 24), rf.decode_double(o + 32), rf.decode_double(o + 40)])
		print("  整对总冲量=%.4f，各点冲量绝对值之和=%.4f（比值 %.3f）" % [total, s, s / maxf(total, 1e-9)])
	quit(0)

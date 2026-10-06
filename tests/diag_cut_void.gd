extends SceneTree
## 复现用户场景：**切割地面 -> 大部分碎片掉进虚空**（demo 的剔除节奏）。
## 每帧记录：子步数 / 活着的刚体 / Rapier 侧刚体 / 步进耗时。
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const Destruction := preload("res://src/core/destruction.gd")

const WORLD_W := 768
const WORLD_H := 320
const CULL := Rect2(-600, -800, WORLD_W + 1200, WORLD_H + 1400)

func _native_count(w) -> int:
	var cmds := PackedByteArray()
	cmds.resize(1)
	cmds.encode_u8(0, 13)
	var res: PackedByteArray = w._rp_send(cmds, 4)
	return res.decode_s32(4) if res.size() >= 8 else -1

func _initialize() -> void:
	var w := PWorld.new()
	w.gravity = Vector2(0, 300)
	var ground := PBody.new()
	ground.make_static()
	ground.position = Vector2(0, 220)
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, WORLD_W, 100), 1)
	w.add_body(ground, [s])

	var tick := 0
	var cut_i := 0
	var max_step := 0.0
	var t_report := Time.get_ticks_usec()
	for frame in 1800:                      # 30 秒 @60Hz
		# 每 30 帧切一刀（局部坐标：竖直切穿地面 -> 掉成两半/碎片）
		if frame % 30 == 0 and cut_i < 40:
			cut_i += 1
			var x := 40 + (cut_i * 17) % (WORLD_W - 80)
			w.fracture(ground, Destruction.Damage.segment(
				Vector2(x, -5), Vector2(x, 105), 3.0))
		# demo 的节奏：每 60 帧剔除一次 + 预算
		if frame % 60 == 0:
			w.cull_outside(CULL)
			w.enforce_body_budget()
		var t0 := Time.get_ticks_usec()
		w.step(1.0 / 60.0)
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		max_step = maxf(max_step, ms)
		if frame % 300 == 0:
			print("帧 %4d | 子步 %3d | 活刚体 %4d | **Rapier 刚体 %5d** | 本步 %6.3f ms | 峰值 %7.3f ms" % [
				frame, w.last_substeps, w.bodies.size(), _native_count(w), ms, max_step])
	print("总耗时 %.1f s（模拟 30 s 的场景）" % (float(Time.get_ticks_usec() - t_report) / 1e6))
	quit(0)

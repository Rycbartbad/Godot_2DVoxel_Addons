extends SceneTree
## 验证 physics_step_finished 的三条契约：零步不发 / 一步一次 / 一帧多步多次。
##
## ⚠️ 故意**不把节点放进树**：PixelWorld._ready() -> rebuild() 在 headless 下会中止
##    （本探针第一版就死在这里，而且什么都不打 —— _initialize 里的运行时错误会中断它）。
##    不放进树 -> _ready 不跑 -> 手动给 world 即可测步进逻辑。
const PixelWorld := preload("res://src/nodes/pixel_world.gd")
const PWorld := preload("res://src/physics/pworld.gd")

func _initialize() -> void:
	var pw = PixelWorld.new()
	pw.world = PWorld.new()
	pw.auto_render = false
	var n := [0]
	pw.physics_step_finished.connect(func(_w): n[0] += 1)
	print("fixed_dt = %.6f, max_substeps = %d" % [pw.fixed_dt, pw.max_substeps])

	var c0: int = n[0]
	pw._physics_process(pw.fixed_dt * 0.4)
	print("零步帧（0.4 步）：发出 %d 次，期望 0" % (n[0] - c0))

	var c1: int = n[0]
	pw._physics_process(pw.fixed_dt)
	print("一步帧（1.0 步）：发出 %d 次，期望 1" % (n[0] - c1))

	var c2: int = n[0]
	pw._physics_process(pw.fixed_dt * 2.5)
	print("多步帧（2.5 步）：发出 %d 次，期望 2" % (n[0] - c2))

	var c3: int = n[0]
	pw._physics_process(pw.fixed_dt * 10.0)
	print("超限帧（10 步 > max_substeps）：发出 %d 次，期望 %d" % [n[0] - c3, pw.max_substeps])

	print("---")
	var want: int = 1 + 2 + pw.max_substeps
	var got: int = n[0] - c0
	print("总计 %d 次（期望 %d）；契约%s" % [got, want, "成立 ✓" if got == want else "不成立 ✗"])
	quit(0 if got == want else 1)

extends SceneTree
## 最小复现：只建一个 PWorld + 一个 RapierPhys，退出时看有没有泄漏报告。
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _initialize() -> void:
	var mode := OS.get_environment("REPRO_MODE")
	if mode == "":
		mode = "world"
	print("REPRO_MODE = " + mode)
	if mode == "raw":
		# 只建原生实例，不建 PWorld
		var rp = ClassDB.instantiate("RapierPhys")
		print("raw rp = %s" % str(rp))
		rp = null
	elif mode == "body":
		# PWorld + 一个刚体（会走 rebuild -> density_callable()）
		var w := PWorld.new()
		w._rp_ensure()
		var b := PBody.new()
		var s := PixelShape.new()
		s.fill_rect(Rect2i(0, 0, 8, 8), 1)
		w.add_body(b, [s], Callable(), true)
		print("body ok, bodies=%d" % w.bodies.size())
	else:
		var w2 := PWorld.new()
		w2._rp_ensure()
		print("world rp = %s" % str(w2._rp))
	quit(0)

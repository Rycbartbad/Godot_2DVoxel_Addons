extends SceneTree
## ccd_enabled=false 时，Rapier 自带的 CCD 还会兜住吗？
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _shape(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _run(speed: float, ignore: float, ccd_enabled: bool, ccd_sub: int) -> Array:
	var w := PWorld.new()
	w.gravity = Vector2.ZERO
	w.ccd_enabled = ccd_enabled
	w.rp_ccd_substeps = ccd_sub
	w._rp_ccd_substeps_pushed = -1        # 强制重推（否则 0 会被"值没变就不推"吞掉）
	var wall := PBody.new()
	wall.make_static()
	w.add_body(wall, [_shape(4, 300)])
	var f := PBody.new()
	f.position = Vector2(-80, 0)
	w.add_body(f, [_shape(10, 10)])
	f.linear_velocity = Vector2(speed, 0)
	w.ccd_ignore_mass = ignore
	var peak := 0
	for k in 10:
		w.step(1.0 / 60.0)
		peak = maxi(peak, w.last_substeps)
	return [f.position.x, peak]

func _initialize() -> void:
	print("=== 30000 px/s、豁免开、撞 4px 墙：谁兜住？ ===")
	print("  %-14s %-18s %-12s %s" % ["ccd_enabled", "rp_ccd_substeps", "10步后x", "峰值子步"])
	for ccd in [true, false]:
		for sub in [1, 0]:
			var r: Array = _run(30000.0, 200.0, ccd, sub)
			print("  %-14s %-18s %-12s %s" % [
				str(ccd), str(sub), "%.1f" % r[0],
				"%d  %s" % [r[1], "**穿过去了**" if r[0] > 20.0 else "挡住"]])
	print("")
	print("=== 对照：豁免关（引擎子步在管）===")
	for ccd in [true, false]:
		var r: Array = _run(30000.0, 0.0, ccd, 1)
		print("  ccd_enabled=%-6s -> x %9.1f  %s（峰值子步 %d）" % [
			str(ccd), r[0], "**穿**" if r[0] > 20.0 else "挡住", r[1]])
	quit(0)

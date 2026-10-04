extends SceneTree
## 验证**门面**路径：Godot 使用者只认识 PixelPhysics 一个类，能不能拿到接触数据。
## ⚠️ 这就是"在 Godot 中这些数据会怎么给出"的答案 —— 不碰 world、不碰 PBody。
func _initialize() -> void:
	# ⚠️ 这里用 preload 而不是 class_name：headless 下全局类名缓存可能还没扫到 addon，
	#    直接用 PixelPhysics 会报 "Identifier not declared"。正常编辑器项目里 class_name 可用。
	const PixelPhysicsScript := preload("res://addons/pixel_destruction/pixel_physics.gd")
	var px = PixelPhysicsScript.new()
	get_root().add_child(px)
	await process_frame
	px.add_ground(Rect2(-200, 100, 400, 24), 1)
	var ball = px.spawn_circle(Vector2(0, 60), 14, 2)
	ball.linear_velocity = Vector2(0, 900)
	var found := false
	for i in 90:
		px.step(1.0 / 60.0)
		var n: int = px.contact_pair_count()
		if n > 0 and not found:
			found = true
			var info: Dictionary = px.contact_info(0)
			var pts: Array = info["points"]
			print("门面：接触对 %d，点数 %d，总冲量 %.4f，id=(%d,%d)" % [
				n, pts.size(), info["total_impulse"], info["id_a"], info["id_b"]])
			var s := 0.0
			for p in pts:
				s += absf(p["impulse"])
				print("  点 pos=(%.2f,%.2f) dist=%.3f 冲量=%.4f" % [
					p["position"].x, p["position"].y, p["dist"], p["impulse"]])
			print("  各点之和 = %.4f（/ 总冲量 = %.4f）" % [s, s / maxf(info["total_impulse"], 1e-9)])
			# 门面的损伤入口
			for e in px.contact_entries(0, 8.0):
				print("  入口 point=(%.2f,%.2f) share=%.4f radius=%.4f penetrating=%s" % [
					e["point"].x, e["point"].y, e["share"], e["radius"], str(e["penetrating"])])
			break
	if not found:
		print("门面：整段没出现接触（场景没撞上？）")
	quit(0)

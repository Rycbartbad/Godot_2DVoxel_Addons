extends SceneTree
## 实验（第二版）：在**步进之后**读 Godot 自带物理的接触冲量。
## ⚠️ 第一版在 _integrate_forces 里读，拿到恒为 0 —— 那个回调跑在**求解之前**。
func _initialize() -> void:
	var floor_body := StaticBody2D.new()
	var fs := CollisionShape2D.new()
	var fr := RectangleShape2D.new()
	fr.size = Vector2(800, 40)
	fs.shape = fr
	floor_body.position = Vector2(0, 300)
	floor_body.add_child(fs)
	get_root().add_child(floor_body)

	var box := RigidBody2D.new()
	box.contact_monitor = true
	box.max_contacts_reported = 8
	var bs := CollisionShape2D.new()
	var br := RectangleShape2D.new()
	br.size = Vector2(40, 40)
	bs.shape = br
	box.add_child(bs)
	box.position = Vector2(-100, 260)
	get_root().add_child(box)
	box.linear_velocity = Vector2(300, 0)

	var printed := 0
	for i in 120:
		await physics_frame
		if printed >= 3:
			continue
		var st := PhysicsServer2D.body_get_direct_state(box.get_rid())
		if st == null:
			continue
		var n := st.get_contact_count()
		if n == 0:
			continue
		print("--- 采样 %d（接触点 %d，线速度 %s）---" % [printed, n, str(box.linear_velocity)])
		for k in n:
			var nrm: Vector2 = st.get_contact_local_normal(k)
			var j: Vector2 = st.get_contact_impulse(k)
			var jn := nrm * j.dot(nrm)
			var jt := j - jn
			print("  点%d 法向=%s 冲量=%s | |法向分量|=%.3f |切向分量|=%.3f | |冲量|=%.3f" % [
				k, str(nrm), str(j), jn.length(), jt.length(), j.length()])
		printed += 1
	quit(0)

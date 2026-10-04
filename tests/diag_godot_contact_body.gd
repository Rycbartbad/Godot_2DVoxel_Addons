extends RigidBody2D
## 实验用刚体：打印每个接触点的法向与冲量，拆出法向/切向分量。
## 目的：确定 Godot 的 get_contact_impulse 是"纯法向"还是"含摩擦的合成向量"。
var printed := 0

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if printed >= 3:
		return
	var n := state.get_contact_count()
	if n == 0:
		return
	print("--- 第 %d 次采样（接触点 %d 个，本步线速度 %s）---" % [printed, n, str(state.linear_velocity)])
	for i in n:
		var nrm: Vector2 = state.get_contact_local_normal(i)
		var j: Vector2 = state.get_contact_impulse(i)
		var jn := nrm * j.dot(nrm)
		var jt := j - jn
		print("  点%d 法向=%s 冲量=%s | |法向分量|=%.4f |切向分量|=%.4f | |冲量|=%.4f" % [
			i, str(nrm), str(j), jn.length(), jt.length(), j.length()])
	printed += 1

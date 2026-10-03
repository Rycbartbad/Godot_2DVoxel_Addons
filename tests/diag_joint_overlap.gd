extends SceneTree
## 探针：**互相重合**的两个刚体用关节连起来，会不会抽搐？
##
## ⚠️ 判据不是"求解后的速度" —— 关节和接触的冲量在同一子步里互相抵消，
##    求解后速度看着是 0，但**位置/角度在一步步来回弹**。所以要量：
##      · 逐帧位移/转角的最大跳变（抽搐的直接度量）
##      · 两端之间的接触数（有没有在打）
##      · 关节承受的约束冲量（打得多凶）
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _shape(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _run(label: String, kind: int, overlap: int, contacts: bool) -> void:
	var world := PWorld.new()
	world.gravity = Vector2.ZERO        # 排除重力/地面：只看"关节 vs 接触"
	var a := PBody.new()
	a.position = Vector2(100, 100)
	world.add_body(a, [_shape(16, 16)])
	var b := PBody.new()
	b.position = Vector2(100 + 16 - overlap, 100)
	world.add_body(b, [_shape(16, 16)])
	var j = null
	match kind:
		0: j = world.add_weld(a, b, Vector2(108, 108))
		1: j = world.add_hinge(a, b, Vector2(108, 108))
	j.contacts_enabled = contacts
	j.break_impulse = 1.0e12           # 只是为了让冲量读回生效（诊断用）
	var max_v := 0.0
	var max_jump := 0.0
	var max_contacts := 0
	var prev_a := a.position
	var prev_b := b.position
	for i in 240:
		world.step(1.0 / 60.0)
		max_v = maxf(max_v, b.linear_velocity.length() + absf(b.angular_velocity))
		max_jump = maxf(max_jump, a.position.distance_to(prev_a) + b.position.distance_to(prev_b))
		prev_a = a.position
		prev_b = b.position
		max_contacts = maxi(max_contacts, world.last_contacts)
	print("%-22s 重合%2dpx 接触=%-5s -> 逐帧跳变 %7.4f  最大速度 %7.2f  接触数 %2d  关节冲量 %8.1f" % [
		label, overlap, str(contacts), max_jump, max_v, max_contacts, j.last_impulse])

func _initialize() -> void:
	print("=== 两个动态刚体重合 + 关节（零重力）===")
	_run("焊接/不碰", 0, 8, false)
	_run("焊接/互碰", 0, 8, true)
	_run("焊接/不碰(1px)", 0, 1, false)
	_run("焊接/互碰(1px)", 0, 1, true)
	_run("铰链/不碰", 1, 8, false)
	_run("铰链/互碰", 1, 8, true)
	quit(0)
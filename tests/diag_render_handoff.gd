extends SceneTree
## R2 核验探针（**不是闸门**，用来看清楚"新建 holder / 贴图交接"那一刻到底发生了什么）
##
## 查三件事：
##   ① 新建 holder 与它的块 sprite，**同一帧**里的变换/offset 对不对（有没有"先出现在旧位置"）
##   ② forget() 之后，旧节点**是不是还在树里**（同帧交接：会不会残留一帧）
##   ③ 本项目的物理插值设置（以及节点有没有 opt-in）—— 决定"插值历史"这条假设是否成立
const PixelWorld := preload("res://src/nodes/pixel_world.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const PixelRenderer := preload("res://src/render/pixel_renderer.gd")

func _shape(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _initialize() -> void:
	print("=== R2 核验：新建 holder / 贴图交接 ===")
	var rend := PixelRenderer.new()
	get_root().add_child(rend)
	var w := PWorld.new()
	w.gravity = Vector2(0, 400)

	var ground := PBody.new()
	ground.position = Vector2(-100, 200)
	ground.make_static()
	w.add_body(ground, [_shape(400, 20)], Callable(), true)

	var b := PBody.new()
	b.position = Vector2(-13, 100)      # ⚠️ 故意不是 64 的倍数（碎片的 aabb 起点就是这样）
	b.rotation = 0.3
	w.add_body(b, [_shape(40, 40)], Callable(), true)
	w.step(1.0 / 60.0)

	# ① 新建 holder 的**同一帧**变换
	rend.sync(b)
	var holder: Node2D = rend._nodes.get(b.id)
	var ok_pos: bool = holder != null and holder.transform.origin.is_equal_approx(b.position)
	var ok_rot: bool = holder != null and absf(holder.transform.get_rotation() - b.rotation) < 1e-5
	print("① holder 存在=%s 位置对=%s（%s vs %s） 旋转对=%s" % [
		str(holder != null), str(ok_pos), str(holder.transform.origin if holder else Vector2.ZERO),
		str(b.position), str(ok_rot)])
	var aabb: Rect2i = rend._local_bounds(b)
	var off_bad := 0
	var off_n := 0
	for key in (rend._tiles.get(b.id, {}) as Dictionary):
		var sp: Sprite2D = (rend._tiles[b.id] as Dictionary)[key]
		var tx: int = (key as Vector2i).x
		var ty: int = (key as Vector2i).y
		# 期望 offset = 区域原点（不是块的网格原点）—— 独立算出来的
		var want := Vector2(maxi(tx << 6, aabb.position.x), maxi(ty << 6, aabb.position.y))
		off_n += 1
		if not sp.offset.is_equal_approx(want):
			off_bad += 1
			print("   ⚠️ 块 %s offset=%s 期望 %s" % [str(key), str(sp.offset), str(want)])
	print("① 块数=%d，offset 与区域原点不一致的=%d" % [off_n, off_bad])

	# ② forget 之后旧节点还在不在树里（同帧交接）
	var old: Node2D = rend._nodes.get(b.id)     # ⚠️ 必须在 forget **之前**抓住它
	var n_before: int = old.get_child_count()
	var sp_before: Sprite2D = (rend._tiles[b.id] as Dictionary).values()[0]
	rend.forget(b.id)
	print("② forget 之后：账上有键=%s | 旧 holder 有效=%s is_inside_tree=%s queued_free=%s | 旧块 sprite 有效=%s is_inside_tree=%s" % [
		str(rend._nodes.has(b.id)), str(is_instance_valid(old)),
		str(is_instance_valid(old) and old.is_inside_tree()),
		str(is_instance_valid(old) and old.is_queued_for_deletion()),
		str(is_instance_valid(sp_before)),
		str(is_instance_valid(sp_before) and sp_before.is_inside_tree())])
	await process_frame
	print("② 下一帧：旧 holder 还有效=%s" % str(old != null and is_instance_valid(old)))

	# ③ 物理插值设置
	print("③ physics/common/physics_interpolation = %s；PixelRenderer 有 physics_interpolation_mode 吗 = %s" % [
		str(ProjectSettings.get_setting("physics/common/physics_interpolation", "(未设置)")),
		str("physics_interpolation_mode" in rend)])
	if "physics_interpolation_mode" in rend:
		print("   PixelRenderer.physics_interpolation_mode = %s" % str(rend.physics_interpolation_mode))
	quit(0)
extends SceneTree
## 手册自检：把手册里出现的 API 名字全部拿去和真实代码对一遍。
## 教错 API 的手册比没有手册更糟。
## ⚠️ 用**运行时 load** 而不是 preload。
##
## addon 是**构建产物**（tools/build_addon.py 生成），默认不在项目树里 ——
## 它的 class_name 与 src/ 必然重名，住在项目树里会让编辑器报
## "Class X hides a global script class"，而且会级联到编译失败。
## 所以它构建完就移出项目树（CI 里也一样）。
##
## preload 是**编译期**的：文件不在就直接解析失败，连整个脚本都加载不了。
## 运行时 load 缺席时返回 null，可以优雅跳过。
const ADDON := "res://addons/pixel_destruction/"
var Facade: GDScript = null
var PixelShape: GDScript = null
var PWorld: GDScript = null
var PBody: GDScript = null

var _bad: Array = []

func _check(obj_name: String, obj, names: Array) -> void:
	for n in names:
		if not obj.has_method(n):
			_bad.append("%s.%s" % [obj_name, n])

func _check_prop(obj_name: String, obj, names: Array) -> void:
	for n in names:
		var found := false
		for p in obj.get_property_list():
			# ⚠️ get_property_list() 的 name 是 StringName，直接和 String 比会不相等
			if String(p["name"]) == n:
				found = true
				break
		if not found:
			_bad.append("%s.%s (属性)" % [obj_name, n])

func _initialize() -> void:
	# addon 缺席就跳过 —— 它是构建产物，不在项目树里是**正常状态**。
	Facade = load(ADDON + "pixel_physics.gd")
	PixelShape = load(ADDON + "core/pixel_shape.gd")
	PWorld = load(ADDON + "physics/pworld.gd")
	PBody = load(ADDON + "physics/pbody.gd")
	if Facade == null:
		print("=== 跳过：addon 未构建（python tools/build_addon.py 生成后再跑）===")
		quit(0)
		return
	var f = Facade.new()
	var w = PWorld.new()
	var b = PBody.new()
	var s = PixelShape.new()

	# ---- 手册里用到的 facade 方法 ----
	_check("PixelPhysics", f, [
		"configure", "define_material", "material_color", "material_density", "material_at",
		"add_ground", "spawn_rect", "spawn_circle", "spawn_shape", "spawn_from_grid", "despawn",
		"carve_circle", "carve_rect", "cut", "explode", "paint_circle", "set_body_material",
		"split_shape", "merge_shape", "is_broken", "bodies",
		"push", "push_at", "spin", "impulse", "set_gravity_scale", "set_velocity",
		"raycast", "closest_point", "bodies_in", "query_reject_body", "query_clear_filters",
		"grab_at", "drag_to", "release", "has_grab",
		"set_tag", "find_body", "find_bodies", "find_shapes", "tag_value", "has_tag", "remove_tag",
		"shape_material_at", "center_of_mass", "step", "resync", "renderer",
		# 动力学量（甲方要求）
		"spin", "torque_impulse", "angular_velocity_of", "momentum", "angular_momentum",
		"angular_momentum_about", "kinetic_energy", "mass_of", "inertia_of",
		"total_momentum", "total_angular_momentum", "total_kinetic_energy", "system_center_of_mass",
	])
	# world / auto_step / auto_render 是**属性**不是方法，走 _check_prop
	_check_prop("PixelPhysics", f, ["world"])

	# ---- 手册里用到的 world / body / shape 成员 ----
	_check_prop("PWorld", w, ["contacts", "contact_events_enabled", "sleeping_enabled",
		"ccd_max_substeps", "max_speculative_margin", "ccd_max_motion", "sleep_surface",
		"material_density", "gravity"])
	_check("PWorld", w, ["step"])
	_check("PBody", b, ["to_local", "to_world", "velocity_at", "make_static"])
	_check_prop("PBody", b, ["shapes"])
	_check("PixelShape", s, ["get_pixel", "set_pixel", "get_aux", "set_aux", "clear_pixel",
		"fill_rect", "count_by_material", "dirty_chunks", "has_dirty", "clear_dirty",
		"mark_dirty", "mark_dirty_key", "flood", "neighbors"])
	# component_map 在 ShapeOps 上（PixelShape 不能 preload Destruction，会成环）
	# ⚠️ 用 src/ 而不是 addons/ 路径：addon 目录被 .gdignore 忽略了
	#    （它是 src/ 的拷贝，同时存在会撞 UID 和 class_name）。
	#    addon 自身的引用可解析性由 tools/check_addon.py 做文本校验。
	var so = preload("res://src/core/shape_ops.gd").new()
	if not so.has_method("component_map"):
		_bad.append("ShapeOps.component_map")
	_check_prop("PixelShape", s, ["chunks"])
	# 静态成员
	for n in ["make_key", "key_x", "key_y", "OFFSETS_4", "OFFSETS_8"]:
		var ok := false
		for p in s.get_property_list():
			if String(p["name"]) == n:
				ok = true
		if not ok and s.get(n) == null:
			_bad.append("PixelShape.%s (静态)" % n)

	if _bad.is_empty():
		print("=== 手册引用的 API 全部存在 ===")
	else:
		print("=== 有 %d 处对不上 ===" % _bad.size())
		for x in _bad:
			print("  " + x)
	quit(0 if _bad.is_empty() else 1)

extends SceneTree
## 碰撞层/掩码自检。
##
## 三层都要测到，缺一层都会静默失效：
##   1. 物理侧：Rapier 的 InteractionGroups 真的挡住了不该碰的（**双向**判据）；
##   2. 重建碰撞体之后分组不丢（本文件里最容易静默回归的一条）；
##   3. 查询侧：Query.require / include 只看见要求的层。

const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const Query := preload("res://src/physics/query.gd")

const ALL := 0xFFFFFFFF
const L1 := 1
const L2 := 2
const L3 := 4

var _pass := 0
var _fail := 0

func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
		print("  PASS  ", name, "  ", detail)
	else:
		_fail += 1
		print("  FAIL  ", name, "  ", detail)

func _box(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

func _spawn(world: PWorld, pos: Vector2, layer: int) -> PBody:
	var b := PBody.new()
	b.position = pos
	b.collision_layer = layer
	world.add_body(b, [_box(16, 16)])
	return b

## 正碰：A 以 120 px/s 撞向**静态** B，跑 1 秒。返回"撞上了吗"。
##
## ⚠️ B 必须是**静态**的。第一版让 B 也是动态体，于是 A 撞上之后推着 B 一起走
##    （两者都在 x≈160~180），判据"停在 B 左侧"永远为假 —— 看起来像"没碰上"，
##    其实是"碰上了并且推动了"。接触数 c=1 已经证明在碰。
## 不撞的话 A 走到 x≈200；撞上则停在 B 左侧（x≈124）。
func _head_on(a_layer: int, a_mask: int, b_layer: int, b_mask: int) -> bool:
	var world := PWorld.new()
	world.gravity = Vector2.ZERO
	var a := PBody.new()
	a.position = Vector2(100, 100)
	a.collision_layer = a_layer
	a.collision_mask = a_mask
	a.linear_velocity = Vector2(120, 0)
	world.add_body(a, [_box(16, 16)])
	var b := PBody.new()
	b.position = Vector2(140, 100)
	b.collision_layer = b_layer
	b.collision_mask = b_mask
	b.make_static()
	world.add_body(b, [_box(16, 16)])
	for i in 60:
		world.step(1.0 / 60.0)
	return a.position.x < 138.0

## 擦掉 A 的一角 -> rebuild() -> Rapier 侧重建碰撞体。
## 分组如果没跟着重推，A 会退回"和所有层都碰"，于是撞上 B（layer 不同也撞）。
func _rebuild_keeps_filter() -> bool:
	var world := PWorld.new()
	world.gravity = Vector2.ZERO
	var a := PBody.new()
	a.position = Vector2(100, 100)
	a.collision_layer = L1
	a.collision_mask = L1
	world.add_body(a, [_box(16, 16)])
	var b := _spawn(world, Vector2(200, 100), L2)
	b.make_static()
	world.step(1.0 / 60.0)
	world.damage_circle(a.com_world(), 2.0, 1)
	world.step(1.0 / 60.0)
	a.linear_velocity = Vector2(120, 0)
	for i in 120:
		world.step(1.0 / 60.0)
	# 分组保住了 -> A 穿过 B 的区域（两秒走 ~170 px，从 100 到 ~270）；
	# 分组丢了（退回全 1）-> A 停在 B 左侧（x≈184）。
	# ⚠️ 阈值 195 卡在两者中间；起点和阈值都是量出来的，不是猜的
	#    （线性阻尼 0.35 下 A 一秒只走 ~101 px）。
	return a.position.x > 195.0

func _test_query_filter() -> void:
	print("[查询过滤]")
	var world := PWorld.new()
	world.gravity = Vector2.ZERO
	var b1 := _spawn(world, Vector2(100, 100), L1)
	var b2 := _spawn(world, Vector2(140, 100), L2)
	var b3 := _spawn(world, Vector2(180, 100), L3)
	Query.attach(world)
	var h := Query.raycast(Vector2(0, 108), Vector2(1, 0), 400.0)
	_check("默认打到最近的（L1）", h.hit and h.body == b1, "body=%s" % str(h.body))
	Query.require(L2)
	h = Query.raycast(Vector2(0, 108), Vector2(1, 0), 400.0)
	_check("require(L2) 只看得见 L2", h.hit and h.body == b2, "body=%s" % str(h.body))
	Query.require(L3)
	h = Query.raycast(Vector2(0, 108), Vector2(1, 0), 400.0)
	_check("require(L3) 只看得见 L3", h.hit and h.body == b3, "body=%s" % str(h.body))
	Query.require(0)
	h = Query.raycast(Vector2(0, 108), Vector2(1, 0), 400.0)
	_check("require(0) 谁都看不见", not h.hit)
	Query.require(L2)
	Query.include(L3)
	_check("include 追加层（aabb 查询同样受过滤）", Query.aabb_bodies(Rect2(0, 90, 400, 40)).size() == 2,
		"n=%d" % Query.aabb_bodies(Rect2(0, 90, 400, 40)).size())
	Query.clear_filters()
	_check("clear_filters 之后全都能看见", Query.aabb_bodies(Rect2(0, 90, 400, 40)).size() == 3,
		"n=%d" % Query.aabb_bodies(Rect2(0, 90, 400, 40)).size())
	h = Query.raycast(Vector2(0, 108), Vector2(1, 0), 400.0)
	_check("clear_filters 之后射线也恢复", h.hit and h.body == b1)
	Query.detach()

func _initialize() -> void:
	print("=== collision filter self-test ===")
	print("[物理：双向判据]")
	# ⚠️ 判据是**双向**的：mask = ALL 时"层不同"**不会**互相排斥
	#    （(1 & ALL) != 0 且 (2 & ALL) != 0 两条都成立）。
	#    第一版把"层不同"当成"不碰"，于是这一条反过来报错 —— 错的是判据，不是实现。
	_check("同层互碰", _head_on(L1, ALL, L1, ALL))
	_check("mask=ALL 时层不同也碰", _head_on(L1, ALL, L2, ALL))
	_check("我方的掩码不含对方 -> 不碰", not _head_on(L1, L1, L2, ALL))
	_check("对方的掩码不含我 -> 不碰（双向）", not _head_on(L1, ALL, L2, L2))
	_check("双方都同意才碰", _head_on(L1, L2, L2, L1))
	_check("一方全要也碰", _head_on(L1, L2, L2, ALL))
	_check("layer=0 是幽灵", not _head_on(0, ALL, L1, ALL))
	_check("mask=0 谁都不碰", not _head_on(L1, 0, L1, ALL))
	print("[物理：重建碰撞体之后]")
	_check("擦一块地形后掩码还在", _rebuild_keeps_filter())
	_test_query_filter()
	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

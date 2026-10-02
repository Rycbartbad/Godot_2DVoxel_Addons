class_name PixelPhysics
extends Node2D
## pixel_destruction 的**门面** —— 调用方只需要认识这一个类。
##
## ## 为什么需要这一层
##
## 引擎内部是 8 个互相 preload 的类，各自暴露一堆字段。直接用它们意味着调用方要
## 自己保证一堆**跨对象的一致性**，而其中任何一条漏掉都是静默的怪 bug：
##
##   · 材质颜色在 `PixelRenderer.palette`、密度在 `PWorld.material_density` —— 两张表要手动同步；
##   · 破坏会**增删刚体**，渲染层必须跟着 prune，否则残留幽灵贴图；
##   · 破坏的坐标是 **Shape 局部像素空间**，而游戏逻辑手里是世界坐标；
##   · `manifolds` 有三个消费者（求解/唤醒/休眠），走不走原生路径必须**全步一致**；
##   · 外力是持久累加器，忘了 `clear_forces()` 就会越加越大。
##
## 门面把这些一次性收口：**一个世界、一张材质表、一套世界坐标、一份内部标志**。
##
## ## 用法
##
## 因为注册了 `class_name`，调用方**连 preload 都不用写**：
##
## ```gdscript
## var px := PixelPhysics.new()
## add_child(px)                                  # 加进树里就会自动 _physics_process
##
## px.define_material(1, Color.SLATE_GRAY, 2.5)   # 石头：颜色 + 密度一次设好
## px.define_material(2, Color.SANDY_BROWN, 0.6)  # 木头
## px.add_ground(Rect2(-400, 300, 800, 40), 1)
##
## var ball := px.spawn_circle(Vector2(0, 0), 14, 2)
## px.explode(Vector2(0, 300), 60.0, 400.0)       # 世界坐标
## px.drag_to(mouse_world_position)               # 拖动
## ```
##
## 不想加进树里（无头测试、自己控节奏）就不 add_child，手动 `step(delta)` 即可。

const PBody := preload("res://addons/pixel_destruction/physics/pbody.gd")
const PWorld := preload("res://addons/pixel_destruction/physics/pworld.gd")
const PixelShape := preload("res://addons/pixel_destruction/core/pixel_shape.gd")
const PixelRenderer := preload("res://addons/pixel_destruction/render/pixel_renderer.gd")
const Query := preload("res://addons/pixel_destruction/physics/query.gd")
const ShapeOps := preload("res://addons/pixel_destruction/core/shape_ops.gd")

## 世界（想直接调底层接口时用它，但优先用门面的方法）
var world: PWorld

## 加进场景树后是否自动 _physics_process
var auto_step := true
## 是否自动维护渲染层（关掉就完全无渲染依赖）
var auto_render := true

var _palette: Array = [Color(0, 0, 0, 0)]
var _renderer: Node2D = null
var _accum := 0.0


func _init() -> void:
	world = PWorld.new()
	Query.attach(world)          # 查询是模块级的，建世界时挂上


func _ready() -> void:
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if auto_step:
		step(delta)


# ============================================================ 配置

## 一次性配置。认识的键（都给默认值，不传也行）：
##   gravity: Vector2      默认 (0, 900)
##   fixed_dt: float       物理步长，默认 1/60
##   max_substeps: float   每帧最多几步，默认 4
##   sleeping: bool        是否允许休眠，默认 true
##   terminal_speed: float 终端速度，默认 650
##   native: bool          是否启用扩展加速（没有扩展会自动回退），默认 true
##   auto_render: bool     默认 true
func configure(opts: Dictionary) -> void:
	if opts.has("gravity"):
		world.gravity = opts["gravity"]
	if opts.has("fixed_dt"):
		world.fixed_dt = opts["fixed_dt"]
	if opts.has("max_substeps"):
		world.max_substeps = int(opts["max_substeps"])
	if opts.has("sleeping"):
		world.sleeping_enabled = bool(opts["sleeping"])
	if opts.has("terminal_speed"):
		world.terminal_speed = opts["terminal_speed"]
	if opts.has("native"):
		var on := bool(opts["native"])
		world.use_native_solve = on
		world.use_native_broadphase = on
		world.use_native_collide = on
	if opts.has("auto_render"):
		auto_render = bool(opts["auto_render"])


func set_gravity(g: Vector2) -> void:
	world.gravity = g


# ============================================================ 材质（颜色 + 密度 + 质量）

## 定义一种材质：**颜色和密度一次设好**，不用再去维护两张表。
## id 从 1 开始（0 保留给"空"）。
func define_material(id: int, color: Color, density: float = 1.0) -> void:
	if id <= 0:
		push_error("材质 id 必须 > 0（0 保留给「空」）")
		return
	while _palette.size() <= id:
		_palette.append(Color(1, 1, 1))
	_palette[id] = color
	world.set_material_density(id, density)
	if _renderer != null:
		_renderer.palette = _palette
		resync()


func material_color(id: int) -> Color:
	return _palette[id] if id >= 0 and id < _palette.size() else Color(0, 0, 0, 0)


func material_density(id: int) -> float:
	return world.density_of_material(id)


## 把某个刚体的形状整体换成另一种材质并重算质量（"点燃/结冰/腐蚀"）。
func set_body_material(body: PBody, from_material: int, to_material: int) -> int:
	var n := 0
	for s in body.shapes:
		n += (s as PixelShape).remap_material(from_material, to_material)
	if n > 0:
		world.refresh_mass(body)
		_sync_body(body)
	return n


# ============================================================ 造物体

## 静态地面/墙体（世界坐标矩形）。
func add_ground(rect: Rect2, material: int = 1) -> PBody:
	var s := PixelShape.new()
	var size := Vector2i(int(round(rect.size.x)), int(round(rect.size.y)))
	s.fill_rect(Rect2i(Vector2i.ZERO, size), material)
	var b := PBody.new()
	b.position = rect.position
	b.make_static()
	world.add_body(b, [s])
	_sync_body(b)
	return b


## 动态矩形块（世界坐标位置 = 左上角）。
func spawn_rect(pos: Vector2, size: Vector2, material: int = 1) -> PBody:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(Vector2i.ZERO, Vector2i(int(size.x), int(size.y))), material)
	return spawn_shape(pos, s)


## 动态圆盘。
func spawn_circle(pos: Vector2, radius: float, material: int = 1) -> PBody:
	return spawn_shape(pos, make_circle(radius, material))


## 任意像素团（引擎会自动分解成 OBB）。
func spawn_shape(pos: Vector2, shape: PixelShape) -> PBody:
	var b := PBody.new()
	b.position = pos
	world.add_body(b, [shape])
	_sync_body(b)
	return b


## 程序化生成：solid(x, y) -> bool 决定每个像素是否实心。
func spawn_from_grid(pos: Vector2, w: int, h: int, solid: Callable, material: int = 1) -> PBody:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			if solid.call(x, y):
				s.set_pixel(x, y, material)
	return spawn_shape(pos, s)


## 造一个圆盘形状（不建刚体）。spawn_circle 和自定义组合都用它。
func make_circle(radius: float, material: int = 1) -> PixelShape:
	var s := PixelShape.new()
	var r2 := radius * radius
	var n := int(ceil(radius))
	for y in range(-n, n + 1):
		for x in range(-n, n + 1):
			var dx := float(x) + 0.5
			var dy := float(y) + 0.5
			if dx * dx + dy * dy <= r2:
				s.set_pixel(x, y, material)
	return s


func despawn(body: PBody) -> void:
	world.remove_body(body)
	if _renderer != null:
		_renderer.forget(body.id)


# ============================================================ 查询

## 世界里的刚体（**只读**：要增删请用 spawn_*/despawn）。
func bodies() -> Array:
	return world.bodies


func body_count() -> int:
	return world.bodies.size()


## 世界坐标处是什么材质（0 = 空）。
func material_at(world_point: Vector2) -> int:
	for b: PBody in world.bodies:
		if b.rects.is_empty() or not b.aabb.has_point(world_point):
			continue
		var l := b.to_local(world_point)
		var ip := Vector2i(int(floor(l.x)), int(floor(l.y)))
		for s in b.shapes:
			var m: int = (s as PixelShape).get_pixel(ip.x, ip.y)
			if m != 0:
				return m
	return 0


func bodies_in(bounds: Rect2) -> Array:
	var out: Array = []
	for b: PBody in world.bodies:
		if bounds.intersects(b.aabb):
			out.append(b)
	return out


# ============================================================ 力

## 过质心的持续力（每帧调一次；不产生力矩）。会唤醒物体。
func push(body: PBody, force: Vector2) -> void:
	body.add_force(force)


## 在世界坐标点施加持续力 —— 该点不在质心就会同时产生力矩。
func push_at(body: PBody, force: Vector2, world_point: Vector2) -> void:
	body.add_force_at(force, world_point)


## 持续力矩（纯转动）。
func spin(body: PBody, torque: float) -> void:
	body.add_torque(torque)


## 清空某个刚体的外力累加器（不打算继续施力时调一次）。
func clear_forces(body: PBody) -> void:
	body.clear_forces()


## 瞬时冲量。world_point 省略时按过质心处理。
func impulse(body: PBody, j: Vector2, world_point: Vector2 = Vector2.INF) -> void:
	if world_point == Vector2.INF:
		body.apply_central_impulse(j)
	else:
		body.apply_impulse(j, world_point)


# ============================================================ 程序化破坏（全部世界坐标）

## 挖一个圆洞。material_delta > 0 时把破坏边缘换成该材质（烧焦/结冰）。
## 返回新产生的碎片刚体。
func carve_circle(center: Vector2, radius: float,
		material_delta: int = 0, burst_speed: float = 40.0) -> Array:
	return _after_damage(world.damage_circle(center, radius, material_delta, burst_speed))


func carve_rect(center: Vector2, half_size: Vector2,
		material_delta: int = 0, burst_speed: float = 40.0) -> Array:
	return _after_damage(world.damage_rect(center, half_size, material_delta, burst_speed))


## 沿世界坐标线段切一条沟（激光切割）。
func cut(from: Vector2, to: Vector2, radius: float,
		material_delta: int = 0, burst_speed: float = 40.0) -> Array:
	return _after_damage(world.damage_segment(from, to, radius, material_delta, burst_speed))


## 爆炸：半径内按距离衰减推开 + 圆形破坏。
## power 是**速度增量**语义（紧贴爆心的物体大约获得 power 的速度）。
func explode(center: Vector2, radius: float, power: float,
		material_delta: int = 0, burst_speed: float = 40.0) -> Array:
	return _after_damage(world.explode(center, radius, power, material_delta, burst_speed))


## 只改颜色不破坏（世界坐标圆）。返回改动的像素数。
func paint_circle(center: Vector2, radius: float, material: int) -> int:
	var n := world.paint_circle(center, radius, material)
	if n > 0:
		resync()
	return n


# ============================================================ 抓取

## 抓住世界坐标点附近的刚体。返回是否抓住。
func grab_at(world_point: Vector2, accel: float = 2500.0) -> bool:
	var best: PBody = null
	var best_d := 1.0e18
	for b: PBody in world.bodies:
		if b.is_static or b.rects.is_empty() or not b.aabb.grow(2.0).has_point(world_point):
			continue
		var d := b.com_world().distance_squared_to(world_point)
		if d < best_d:
			best_d = d
			best = b
	if best == null:
		return false
	world.grab(best, world_point, accel)
	return true


func drag_to(world_point: Vector2) -> void:
	if world.is_grabbing():
		world.set_grab_target(world_point)


func release() -> void:
	world.release_grab()


func has_grab() -> bool:
	return world.is_grabbing()


# ============================================================ 查询

## 像素级精确的射线检测 —— 直接走体素网格，所以能穿过像素画的空洞。
## 返回 Query.Hit（hit / distance / point / normal / material / body / shape）。
## radius > 0 时是"加粗射线"（扫掠一个半径 radius 的圆）。
func raycast(origin: Vector2, direction: Vector2, max_dist: float,
		radius: float = 0.0) -> Query.Hit:
	return Query.raycast(origin, direction, max_dist, radius)


## 离 origin 最近的实心像素。
func closest_point(origin: Vector2, max_dist: float) -> Query.Hit:
	return Query.closest_point(origin, max_dist)


## 查询时排除某些刚体（一直生效到 query_clear_filters）。
func query_reject_body(body: PBody) -> void:
	Query.reject_body(body)


func query_clear_filters() -> void:
	Query.clear_filters()


# ============================================================ 标签

## 给刚体打标签，之后用 find_body / find_bodies 按名字找它。
func set_tag(body: PBody, tag: String, value = null) -> void:
	body.tags[tag] = value


func has_tag(body: PBody, tag: String) -> bool:
	return body.tags.has(tag)


func tag_value(body: PBody, tag: String):
	return body.tags.get(tag)


func remove_tag(body: PBody, tag: String) -> void:
	body.tags.erase(tag)


func list_tags(body: PBody) -> Array:
	return body.tags.keys()


func find_body(tag: String) -> PBody:
	return world.find_body(tag)


func find_bodies(tag: String) -> Array:
	return world.find_bodies(tag)


func find_shapes(tag: String) -> Array:
	return world.find_shapes(tag)


# ============================================================ 刚体辅助

## 重力缩放：0 = 不受重力，负数 = 反重力。
func set_gravity_scale(body: PBody, scale: float) -> void:
	body.gravity_scale = scale


func set_velocity(body: PBody, v: Vector2) -> void:
	body.linear_velocity = v
	body.awake = true
	body.sleep_timer = 0.0


func set_angular_velocity(body: PBody, w: float) -> void:
	body.angular_velocity = w
	body.awake = true
	body.sleep_timer = 0.0


func set_active(body: PBody, active: bool) -> void:
	body.awake = active
	body.sleep_timer = 0.0


func is_active(body: PBody) -> bool:
	return body.awake


## 刚体上某一点的世界速度（含转动贡献）。
func velocity_at(body: PBody, world_point: Vector2) -> Vector2:
	return body.velocity_at(world_point)


func center_of_mass(body: PBody) -> Vector2:
	return body.com_world()


## ---- 动力学量 ----
##
## ⚠️ 符号约定（2D，Godot 的 y 轴向下）：
##   角速度为正 = 屏幕上**顺时针**转；角动量的符号与它一致。


func mass_of(body: PBody) -> float:
	return body.mass


func inertia_of(body: PBody) -> float:
	return body.inertia


## 角速度，弧度/秒（正 = 屏幕上顺时针）。
func angular_velocity_of(body: PBody) -> float:
	return body.angular_velocity


## 线动量 p = m·v。
func momentum(body: PBody) -> Vector2:
	return body.linear_momentum()


## 角动量 L = I·ω，关于**质心**。
func angular_momentum(body: PBody) -> float:
	return body.angular_momentum()


## 关于世界某点的角动量：L = I·ω + r × m·v。
## 判断"绕某个轴转不转"要用这个（比如绕钉子摆动的木板）。
func angular_momentum_about(body: PBody, world_point: Vector2) -> float:
	return body.angular_momentum_about(world_point)


## 动能 ½m|v|² + ½Iω²。
func kinetic_energy(body: PBody) -> float:
	return body.kinetic_energy()


## 力矩**冲量**（角冲量），一次性改变角速度。
## 持续力矩用 spin()（每帧调）。
func torque_impulse(body: PBody, t: float) -> void:
	body.apply_torque_impulse(t)


## 给整个系统做守恒检查用：总动量 / 关于质心的总角动量 / 总动能 / 整体质心。
##
## ⚠️ 只有**没有外力**（重力、摩擦、阻尼）时总量才守恒。本引擎有线性阻尼
##    （每步 ×1/(1+0.35·dt)），所以长时间会缓慢衰减 —— 短窗口内检查才准。
func total_momentum() -> Vector2:
	return world.total_momentum()


func total_angular_momentum(about: Vector2 = Vector2.INF) -> float:
	var p := world.center_of_mass_world() if about == Vector2.INF else about
	return world.total_angular_momentum(p)


func total_kinetic_energy() -> float:
	return world.total_kinetic_energy()


func system_center_of_mass() -> Vector2:
	return world.center_of_mass_world()


func bounds(body: PBody) -> Rect2:
	return body.aabb


## 是否已经被打碎（形状全空）。
func is_broken(body: PBody) -> bool:
	for s in body.shapes:
		if not (s as PixelShape).is_empty():
			return false
	return true


# ============================================================ 形状辅助

func shape_body(shape: PixelShape) -> PBody:
	return shape.owner_body


func shape_bounds(shape: PixelShape) -> Rect2i:
	return shape.local_aabb()


func shape_size(shape: PixelShape) -> Vector2i:
	return shape.local_aabb().size


func shape_voxels(shape: PixelShape) -> int:
	return shape.pixel_count()


## **世界坐标**处的材质 id（0 = 空）。
func shape_material_at(shape: PixelShape, world_point: Vector2) -> int:
	return ShapeOps.material_at_position(shape, world_point)


## 形状局部像素坐标处的材质 id。
func shape_material_at_index(shape: PixelShape, x: int, y: int) -> int:
	return shape.get_pixel(x, y)


func set_shape_density(shape: PixelShape, d: float) -> void:
	ShapeOps.set_density(shape, d)


## 按连通性切分：最大的那块留在原形状，其余挂到同一刚体上并返回。
func split_shape(shape: PixelShape) -> Array:
	return ShapeOps.split(shape)


## 把同一刚体里与本形状相邻的形状并进来。
func merge_shape(shape: PixelShape) -> PixelShape:
	return ShapeOps.merge(shape)


func is_shape_touching(a: PixelShape, b: PixelShape) -> bool:
	return ShapeOps.is_touching(a, b)


func is_shape_disconnected(shape: PixelShape) -> bool:
	return ShapeOps.is_disconnected(shape)


func shape_closest_point(shape: PixelShape, world_point: Vector2) -> Query.Hit:
	return ShapeOps.closest_point(shape, world_point)


func create_shape(body: PBody, ref: PixelShape = null) -> PixelShape:
	return ShapeOps.create(body, ref)


func clear_shape(shape: PixelShape) -> void:
	ShapeOps.clear(shape)


func copy_shape_content(src: PixelShape, dst: PixelShape) -> void:
	ShapeOps.copy_content(src, dst)


## 用矩形填一段像素（material = 0 等价于擦除）。
func draw_shape_box(shape: PixelShape, rect: Rect2i, material: int = 1) -> void:
	ShapeOps.draw_box(shape, rect, material)


# ============================================================ 推进与渲染

## 推进。内部用固定步长累加器，所以外部帧率波动不会改变物理结果。
## 推进。内部用固定步长累加器，所以外部帧率波动不会改变物理结果。
##
## **外力语义**：底层 PWorld 是持久的 ClearForces 模型（add_force 会一直累积到
## 显式清空）。门面把它改成更贴合游戏循环的语义 —— **力只作用于本帧**，
## 下一帧不 push 就没有力。这样既不用记得清空，也不会出现"忘了清空导致力越滚越大"。
## 需要持续力就每帧 push 一次。
func step(delta: float) -> void:
	_accum += delta
	var steps := 0
	while _accum >= world.fixed_dt and steps < world.max_substeps:
		world.step(world.fixed_dt)
		_accum -= world.fixed_dt
		steps += 1
	if steps == world.max_substeps:
		_accum = 0.0
	_clear_all_forces()
	if auto_render:
		_sync_renderer()


func _clear_all_forces() -> void:
	for b: PBody in world.bodies:
		if not b.is_static:
			b.clear_forces()


## 手动步进一次（无累加器）。
func step_once(dt: float = -1.0) -> void:
	world.step(world.fixed_dt if dt <= 0.0 else dt)
	if auto_render:
		_sync_renderer()


## 渲染层（第一次访问时惰性创建；不想要渲染就永远别访问它）。
func renderer() -> Node2D:
	if _renderer == null:
		_renderer = PixelRenderer.new()
		_renderer.name = "PixelRenderer"
		add_child(_renderer)
		_renderer.palette = _palette
	return _renderer


## 强制重建所有贴图（改了调色板之后调用）。
func resync() -> void:
	if _renderer == null:
		return
	for b: PBody in world.bodies:
		_renderer.sync(b)


func _sync_body(b: PBody) -> void:
	if auto_render and _renderer != null:
		_renderer.sync(b)


func _sync_renderer() -> void:
	if _renderer == null:
		return
	var live := {}
	for b: PBody in world.bodies:
		live[b.id] = true
		_renderer.sync(b)
	_renderer.prune(live)


## 破坏会让引擎增删刚体 —— 门面负责让渲染层跟上，调用方什么都不用做。
func _after_damage(fragments: Array) -> Array:
	if auto_render:
		_sync_renderer()
	return fragments

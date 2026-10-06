extends SceneTree
## **门面（PixelPhysics）路径的渲染归属**闸门。
##
## 为什么单独一条：`internal_render` 这条策略原本只接在**节点层**（PixelWorld）上，
## 门面这条路（代码驱动的项目，比如 ink-2）**完全没接** —— 症状是"明明配了不渲染，
## 破坏之后还是冒出一张停在旧位置的矩形贴图"，而且不报任何错（R1 报的就是这个形状）。
##
## 守三件事：
##   1. `internal_render = false` 的刚体**不进**内部渲染器，而且旧贴图会被**回收**（forget）；
##   2. 正常刚体照常进；
##   3. **静态地形被打坏之后会被重新同步** —— 跳过静态体是**每帧**的优化，
##      不是"静态体永远不用同步"（`_after_damage` 必须 include_static）。
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")

var _pass := 0
var _fail := 0
func _c(n: String, ok: bool, d: String = "") -> void:
	if ok:
		_pass += 1
		print("  PASS  ", n, "  ", d)
	else:
		_fail += 1
		print("  FAIL  ", n, "  ", d)


## 某个刚体的内部贴图上一共画了多少个不透明像素（独立数，不看引擎的说法）。
func _drawn_px(r, body_id: int) -> int:
	var n := 0
	for key in (r._tile_img.get(body_id, {}) as Dictionary):
		var img: Image = (r._tile_img[body_id] as Dictionary)[key]
		for y in img.get_height():
			for x in img.get_width():
				if img.get_pixel(x, y).a > 0.5:
					n += 1
	return n


func _initialize() -> void:
	print("=== 门面路径的渲染归属（internal_render / 静态地形同步）===")
	var FacadeScript = load("res://addons/pixel_destruction/pixel_physics.gd")
	if FacadeScript == null:
		_fail += 1
		print("  FAIL  找不到 res://addons/pixel_destruction/pixel_physics.gd —— 先跑 python tools/build_addon.py")
		print("失败 1 / 1 项")
		quit(1)
		return
	var px = FacadeScript.new()
	px.configure({"gravity": Vector2(0, 600), "auto_render": true})
	get_root().add_child(px)
	# ⚠️⚠️ 渲染层是**惰性创建**的：不先调 renderer()，auto_render 就等于没开
	#    （_sync_renderer 开头就是 `if _renderer == null: return`）。这条很容易踩 ——
	#    "配了 auto_render=true 却什么都没画" 就是这个。
	px.renderer().palette = [Color(0, 0, 0, 0), Color(0.7, 0.7, 0.7)]

	# ---- 1/2. internal_render 的两种取值 ----
	# ⚠️ 变量**不标类型**：门面来自 addon 构建产物，它的 PBody 与本仓库 src/ 的 PBody
	#    是两个不同的脚本类 —— 标了类型就会报 "Trying to assign value of type
	#    'pbody.gd' to a variable of type 'pbody.gd'"（看起来像废话，其实是两个类）。
	var normal = px.spawn_rect(Vector2(0, 0), Vector2(12, 12), 1)
	var hidden = px.spawn_rect(Vector2(40, 0), Vector2(12, 12), 1)
	px.step_once()
	var r = px.renderer()
	_c("正常刚体进了内部渲染器", r._nodes.has(normal.id), "刚体 id=%d" % normal.id)
	_c("默认 internal_render = true", normal.internal_render == true)
	# 先让它进一次（建出贴图），再关掉 —— 关掉之后必须**回收**
	_c("（先确认隐藏的那个也进过，才能验回收）", r._nodes.has(hidden.id))
	hidden.internal_render = false
	px.step_once()
	_c("internal_render=false：不进内部渲染器", not r._nodes.has(hidden.id))
	_c("internal_render=false：旧贴图被回收（forget）", not r._tile_img.has(hidden.id))
	_c("正常的那个不受影响", r._nodes.has(normal.id))

	# ---- 3. 静态地形被打坏之后必须重新同步 ----
	var ground = px.add_ground(Rect2(-100, 200, 200, 60), 1)
	px.step_once()
	var before := _drawn_px(r, ground.id)
	_c("静态地形进了内部渲染器", r._nodes.has(ground.id), "画了 %d 像素" % before)
	# 打一个洞（门面的破坏入口 -> _after_damage -> include_static=true）
	px.carve_circle(Vector2(0, 230), 20.0)
	px.step_once()
	var after := _drawn_px(r, ground.id)
	_c("静态地形被打坏后**重新同步**（画出来的像素变少了）", after < before - 200,
		"%d -> %d 像素（挖掉约 %d）" % [before, after, before - after])
	_c("洞的中心确实没画", _drawn_px(r, ground.id) < before, "")

	print("---")
	if _fail == 0:
		print("全部通过：%d 项断言" % _pass)
	else:
		print("失败 %d / %d 项" % [_fail, _pass + _fail])
	quit(0 if _fail == 0 else 1)

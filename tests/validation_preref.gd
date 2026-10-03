extends SceneTree
## 预引用：`@onready var b = $Placed.body` 到底能不能用？
##
## 甲方要求：PBody 不要"运行时才有"，不要在 _ready 里等一帧、也不要 find 一遍 ——
## 参考 RigidBody2D，直接就能找到，甚至能在 @export 里拖。
##
## ⚠️ 难点是**顺序**：Godot 的 _ready 是子节点先、父节点后，而 PixelWorld 是在自己的
##    _ready 里才 rebuild() 的 —— 子脚本里读 .body 时世界可能根本还没建。
const PixelWorld := preload("res://src/nodes/pixel_world.gd")
const PixelBody2D := preload("res://src/nodes/pixel_body_2d.gd")
const Probe := preload("res://tests/_ready_probe.gd")

var _pass := 0
var _fail := 0
func _c(n: String, ok: bool, d: String = "") -> void:
	if ok:
		_pass += 1
		print("  PASS  ", n, "  ", d)
	else:
		_fail += 1
		print("  FAIL  ", n, "  ", d)


func _initialize() -> void:
	# ⚠️ 必须**等一帧**：SceneTree 脚本的 _initialize 里 add_child 是**不会**同步触发
	#    _ready 的（主循环还没开始跑）。第一版没等，探针的 _ready 根本没执行，
	#    六个断言全读到了默认值（false/null），看起来像功能没做。
	_run.call_deferred()


func _run() -> void:
	await process_frame
	print("=== 预引用（@onready 拿 PBody）===")
	var pw := PixelWorld.new()
	pw.name = "PixelWorld"
	var placed := PixelBody2D.new()
	placed.name = "Placed"
	placed.position = Vector2(100, 40)
	placed.rect_size = Vector2i(16, 16)
	pw.add_child(placed)
	var probe := Probe.new()
	probe.name = "Probe"
	pw.add_child(probe)
	root.add_child(pw)                      # 入树 -> 子节点 _ready 先跑（下一帧）

	_c("探针的 _ready 真的跑了", probe.ran)
	_c("它确实是在世界建好之前跑的", probe.world_was_null)
	_c("子节点 _ready 里读 .body 拿到了东西（不用等一帧）", probe.got != null,
		str(probe.got))
	_c("拿到的就是世界里的那个刚体", pw.world != null and pw.world.bodies.has(probe.got))
	_c("世界没有被重建（引用不作废）", placed.body == probe.got)

	# 幂等：再读一次是同一个
	var again = placed.body
	_c("重复访问幂等", again == probe.got)

	# 模拟"在 @export 里拖一个节点进来"：导出的是节点，读 .body 拿到 PBody
	var dragged: PixelBody2D = placed
	_c("@export 拖节点 -> .body 拿 PBody", dragged.body != null and dragged.body == probe.got)

	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
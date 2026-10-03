extends Node
## 测试辅助：验证 _ready 顺序下的预引用。
##
## ⚠️ Godot 的 _ready 是**子节点先、父节点后** —— 这个探针挂在 PixelWorld 下面，
##    所以它的 _ready 一定早于 PixelWorld._ready()。旧实现里此时 .body 还是 null，
##    只能 await 一帧。现在靠"访问时按需烘焙"拿到。
var got = null
var world_was_null := false
var ran := false

func _ready() -> void:
	ran = true
	var pw := get_parent()
	world_was_null = pw.world == null
	print("[probe] _ready 跑了；此刻 pw.world == null ? %s" % str(world_was_null))
	var n := pw.get_node_or_null("Placed")
	if n != null:
		got = n.body
		print("[probe] 读到 .body = %s" % str(got))
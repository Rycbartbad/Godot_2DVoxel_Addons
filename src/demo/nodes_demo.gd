@tool
extends Node2D
## 节点演示场景的根节点。
##
## 本场景**全部由场景节点摆出来** —— PixelWorld / PixelBody2D / PixelShape2D /
## Camera2D / CanvasLayer + Label 都是普通场景节点，在编辑器里可见、可调。
##
## ⚠️ 这里现在只剩一件事：**设置相机 zoom**。
##    它要按视口高度算（见 PixelScale.render_scale），场景文件里写不成静态值。
##
##    之前这里用 Camera2D.new() 和 Label.new() 把相机和 UI 建出来 ——
##    既和上面那句「全部由场景节点摆出来」自相矛盾，又让编辑器里看不到、调不了。
##    **能用内置节点就用内置节点，能用场景摆就用场景摆。**

const PixelScale := preload("res://src/core/pixel_scale.gd")


func _ready() -> void:
	# 相机是场景里的原生 Camera2D 节点，这里只补上 zoom（依赖视口尺寸）
	var cam := get_node_or_null("Camera2D") as Camera2D
	if cam != null:
		var s := PixelScale.get_scale() * PixelScale.render_scale()
		if s <= 0.0 or not is_finite(s):
			s = 1.0
		cam.zoom = Vector2(s, s)
		cam.make_current()

	if Engine.is_editor_hint():
		return
	if OS.get_cmdline_user_args().has("--shot"):
		await get_tree().create_timer(0.8).timeout
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://nodes_shot.png")
		print("SHOT saved")
		get_tree().quit()

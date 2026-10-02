@tool
extends Node2D
## 节点演示场景的相机与说明。
##
## 本场景**全部由场景节点摆出来**（PixelWorld + PixelBody2D），没有一行生成代码 ——
## 这是"物理引擎对接 Godot 场景编辑器"的示例：
##   · 在编辑器里就能看到像素、碰撞矩形、接触点、速度矢量（@tool + _draw）
##   · 运行时热循环只碰 RefCounted 刚体，不碰这些 Node（实测见 tests/bench_nodes.gd）
##
## 打开 scenes/nodes_demo.tscn，直接按 F5 即可。

const PixelScale := preload("res://src/core/pixel_scale.gd")


func _ready() -> void:
	var cam := Camera2D.new()
	cam.position = Vector2(0, 140)
	var s := PixelScale.get_scale() * PixelScale.render_scale()
	if s <= 0.0 or not is_finite(s):
		s = 1.0
	cam.zoom = Vector2(s, s)
	cam.enabled = true
	add_child(cam)
	cam.make_current()
	if Engine.is_editor_hint():
		return
	var label := Label.new()
	label.position = Vector2(12, 8)
	label.text = "全部由场景节点摆出来（PixelWorld + PixelBody2D）—— 没有生成代码"
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)

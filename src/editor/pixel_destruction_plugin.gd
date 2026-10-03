@tool
extends EditorPlugin
## 本引擎的编辑器插件。
##
## ## 为什么需要它
##
## 在此之前，编辑器集成**全靠 @tool 脚本**：节点在场景树里是通用 Node2D 灰图标，
## PixelWorld / PixelBody2D / PixelShape2D / PixelSprite2D 长得一模一样，分不清。
##
## 这个插件目前只做一件小事：**给节点注册图标**。
## 它刻意保持很小 —— 插件一旦出问题会连编辑器一起拖下水，
## 所以先只上零风险的那部分。
##
## ⚠️ 这个文件在 src/ 与 addon 里**各有一份**（addon 是构建产物）。
##    两边都是同一份代码，改 src/ 的即可。

const ICON_DIR := "res://%s/icons/" % _dir()


## 本插件所在目录（src/editor/ 或 addons/pixel_destruction/editor/），
## 用来拼图标路径 —— 否则 addon 版会去 load res://src/ 下的图标。
func _dir() -> String:
	var here := get_script().resource_path
	return here.get_base_dir().trim_prefix("res://").trim_suffix("/")


func _enter_tree() -> void:
	_register("PixelWorld", "Node2D", "world.svg")
	_register("PixelBody2D", "Node2D", "body.svg")
	_register("PixelShape2D", "Node2D", "shape.svg")
	_register("PixelShapePolygon2D", "Node2D", "shape.svg")
	_register("PixelSprite2D", "Sprite2D", "sprite.svg")


func _exit_tree() -> void:
	remove_custom_type("PixelWorld")
	remove_custom_type("PixelBody2D")
	remove_custom_type("PixelShape2D")
	remove_custom_type("PixelShapePolygon2D")
	remove_custom_type("PixelSprite2D")


func _register(type_name: String, base: String, icon_file: String) -> void:
	var script := _find_script(type_name)
	if script == null:
		push_warning("PixelDestruction 插件：找不到 %s 的脚本，跳过" % type_name)
		return
	var tex: Texture2D = null
	var path := ICON_DIR + icon_file
	if ResourceLoader.exists(path):
		tex = load(path)
	add_custom_type(type_name, base, script, tex)


## 按类名找脚本：优先用全局类（编辑器里已注册），找不到再扫目录。
func _find_script(type_name: String) -> Script:
	if ClassDB.class_exists(type_name):
		return null    # 原生类，不该注册
	var dir := ICON_DIR.get_base_dir()
	for sub in ["", "nodes/", "render/"]:
		var p := dir + "/" + sub + _snake(type_name) + ".gd"
		if ResourceLoader.exists(p):
			return load(p)
	return null


func _snake(s: String) -> String:
	var out := ""
	for i in s.length():
		var c := s[i]
		if c == c.to_upper() and i > 0:
			out += "_"
		out += c.to_lower()
	return out

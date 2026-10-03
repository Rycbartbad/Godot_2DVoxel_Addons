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
## 它刻意保持很小 —— 插件一旦出问题会把编辑器一起拖下水，
## 所以先只上零风险的那部分，跑通了再加工具。
##
## ⚠️ 这个文件在 src/ 与 addon 里**各有一份**（addon 是构建产物）。
##    两边是同一份代码改 src/ 的即可；下面的路径都用相对定位，
##    所以两种布局都能找到脚本和图标。

## 类名 -> 相对本插件目录的脚本路径
const NODE_SCRIPTS := {
	"PixelWorld": "../nodes/pixel_world.gd",
	"PixelBody2D": "../nodes/pixel_body_2d.gd",
	"PixelShape2D": "../nodes/pixel_shape_2d.gd",
	"PixelShapePolygon2D": "../nodes/pixel_shape_polygon_2d.gd",
	"PixelSprite2D": "../nodes/pixel_sprite_2d.gd",
}

## 类名 -> 基类
const NODE_BASES := {
	"PixelWorld": "Node2D",
	"PixelBody2D": "Node2D",
	"PixelShape2D": "Node2D",
	"PixelShapePolygon2D": "Node2D",
	"PixelSprite2D": "Sprite2D",
}


## 本插件所在目录（资源路径形式，带尾部斜杠）。
##
## ⚠️ 不能写成 const —— GDScript 的 const 要求编译期常量，
##    get_script().resource_path 是运行期才有的（第一版就是 const，直接解析失败）。
func _dir() -> String:
	var here: String = (get_script() as Script).resource_path
	return here.get_base_dir() + "/"


func _enter_tree() -> void:
	for type_name in NODE_SCRIPTS:
		_register(type_name)


func _exit_tree() -> void:
	for type_name in NODE_SCRIPTS:
		remove_custom_type(type_name)


func _register(type_name: String) -> void:
	var script_path: String = _dir() + NODE_SCRIPTS[type_name]
	if not ResourceLoader.exists(script_path):
		push_warning("PixelDestruction：找不到 %s（%s），跳过" % [type_name, script_path])
		return
	var script: Script = load(script_path)
	var tex: Texture2D = null
	var icon_path: String = _dir() + "icons/" + _icon_file(type_name)
	if ResourceLoader.exists(icon_path):
		tex = load(icon_path)
	add_custom_type(type_name, NODE_BASES[type_name], script, tex)


func _icon_file(type_name: String) -> String:
	match type_name:
		"PixelWorld":
			return "world.svg"
		"PixelSprite2D":
			return "sprite.svg"
		"PixelBody2D":
			return "body.svg"
		_:
			return "shape.svg"

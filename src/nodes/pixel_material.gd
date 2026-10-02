@tool
class_name PixelMaterial
extends Resource
## 一种材质的**全部属性**，作为 Godot 资源在 Inspector 里编辑。
##
## ## 为什么是 Resource
##
## 在这之前，材质是四张散落的表：
##   · 颜色在 PixelRenderer.palette
##   · 密度在 PWorld.material_density
##   · 抗压/抗剪在 PWorld.material_compress / material_shear
## 改一处忘另一处是**静默 bug**（颜色变了密度没变，物体手感就不对）。
##
## 做成 Resource 之后：
##   · 一个材质 = 一个资源，四处属性天然同步；
##   · 在 Inspector 里编辑，不用写代码；
##   · 可以存成 .tres 复用/共享/版本管理；
##   · 美术能直接改，不用碰脚本。

@export var display_name := "材质"

## 资源 id（1..254）。**0 是"空"**，不能用作实体材质。
## 像素数据里存的就是这个值，所以同一个材质在整条管线上必须用同一个 id。
@export_range(1, 254) var id := 1

@export_group("外观")
@export var color := Color(0.6, 0.6, 0.6)

@export_group("物理")
## 密度：影响质量、转动惯量、碰撞响应
@export var density := 1.0

## 抗压强度（正面顶上去）。0 = **不破坏**（需要显式设成非零才会被破坏判据考虑）
@export var compress_strength := 0.0
## 抗剪强度（横向切/弯）。留负数表示"取抗压的 30%"，多数固体的大致比例。
@export var shear_strength := -1.0


func resolved_shear() -> float:
	return compress_strength * 0.3 if shear_strength < 0.0 else shear_strength


## 强度是否配置过（没配就不该参与破坏判据）
func has_strength() -> bool:
	return compress_strength > 0.0 or resolved_shear() > 0.0

extends SceneTree
## 把手册里的 gdscript 代码块抽出来，**逐个真的编译一遍**。
##
## ## 为什么需要这个
##
## tests/check_manual_api.gd 检查的是「facade 上有没有某个方法」——
## 它抓不到「样例根本跑不起来」：比如 addon 去掉 class_name 之后，
## 手册里那句 PixelPhysics.new() 就失效了，而那个检查完全看不出来。
##
## 教错 API 的手册比没有手册更糟；**样例根本跑不起来**比教错 API 更隐蔽 ——
## 因为它看起来完全正常。
##
## ## 怎么编译
##
## 手册里的块大多是**片段**，不是完整脚本。所以每个块按几种包装依次尝试，
## 只要有一种能通过解析就算合格：
##   1. 原样（本身就是完整脚本）
##   2. 包进 func（语句片段）
##   3. 加上 extends Node2D（用到 self / 节点的片段）
##   4. 既有 extends 又有 func 包装
##
## 全都失败才算不合格，并报告第一种包装的错误信息。

const FILES := [
	"res://README.md",
	"res://docs/manual/README.md",
	"res://docs/manual/cookbook.md",
	"res://docs/manual/nodes.md",
	"res://docs/manual/editor.md",
	"res://docs/manual/performance.md",
	"res://docs/manual/pitfalls.md",
]

## 这些块是「伪代码/示意」，不参与编译（里面明确写了占位符）
const SKIP_MARKERS := ["...", "等等", "省略", "……"]


func _initialize() -> void:
	var total := 0
	var skipped := 0
	var bad := 0
	for f in FILES:
		var blocks := _extract(f)
		for i in blocks.size():
			var code: String = blocks[i]
			var skip := false
			for m in SKIP_MARKERS:
				if code.contains(m):
					skip = true
					break
			if skip:
				skipped += 1
				continue
			total += 1
			var err := _try_compile(code)
			if err != "":
				bad += 1
				print("FAIL  %s  块 #%d" % [f.replace("res://", ""), i + 1])
				print("      %s" % err)
				print("      代码：%s" % code.strip_edges().substr(0, 140).replace("\n", " / "))
	print("=== %d 个代码块参与编译，%d 个失败（%d 个因含占位符跳过）===" % [total, bad, skipped])
	quit(1 if bad > 0 else 0)


## 从 markdown 里抽出 gdscript 代码块
func _extract(path: String) -> Array:
	var out: Array = []
	if not FileAccess.file_exists(path):
		return out
	var f := FileAccess.open(path, FileAccess.READ)
	var cur := ""
	var inside := false
	while not f.eof_reached():
		var line := f.get_line()
		var t := line.strip_edges()
		if not inside and (t == "```gdscript" or t == "``` gdscript"):
			inside = true
			cur = ""
			continue
		if inside and t == "```":
			inside = false
			if not cur.strip_edges().is_empty():
				out.append(cur)
			continue
		if inside:
			cur += line + "\n"
	return out


## 合成前导：声明手册片段里「环境已经提供」的名字。
##
## ⚠️⚠️ 没有它这个检查**全是误报**。
##
## GDScript.reload() 做的是**完整编译**，不是只解析 —— 片段里引用的 px / body /
## shape 都没定义，于是 16 个片段全被判失败。但它们作为**用法示例完全合法**：
## 上下文（一个已经建好的门面、一个刚体变量）不在代码块里，而在正文里。
##
## 这正是 check_docs.py 上踩过的同一个坑：**会误报的闸门比没有闸门更糟** ——
## 它会训练人绕过它。所以这里补一段前导把环境名字声明出来，
## 真正的语法错误（缺冒号、缩进错、括号不配对）照样露得出来。
const PREAMBLE := """extends Node2D

var px = null
var world = null
var body = null
var b = null
var shape = null
var s = null
var c = null
var m = null
var h = null
var frags = null
var gun_body = null
var crate = null
var enemy = null
var muzzle = Vector2.ZERO
var aim_dir = Vector2.ZERO
var delta = 0.0
var e = null
var man = null
"""


## 依次尝试几种包装，全失败就返回第一种的错误
func _try_compile(code: String) -> String:
	var attempts: Array = [
		PREAMBLE + code,
		PREAMBLE + "func _probe() -> void:\n" + _indent(code),
		code,
		PREAMBLE + "func _probe() -> void:\n" + _indent(code) + "\n",
	]
	var first_err := ""
	for idx in attempts.size():
		var g := GDScript.new()
		g.source_code = attempts[idx]
		var e := g.reload()
		if e == OK:
			return ""
		if first_err == "":
			first_err = _err_text(e, attempts[idx])
	return first_err


func _indent(code: String) -> String:
	var out := ""
	for line in code.split("\n"):
		out += ("\t" + line) if not line.strip_edges().is_empty() else "\n"
	return out


func _err_text(e: int, src: String) -> String:
	var first := ""
	for line in src.split("\n"):
		if not line.strip_edges().is_empty():
			first = line.strip_edges()
			break
	return "解析失败（错误码 %d），首行：%s" % [e, first]

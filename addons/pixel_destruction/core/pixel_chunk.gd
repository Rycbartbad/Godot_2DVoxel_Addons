extends RefCounted
## 一个 8x8 像素 chunk。
##
##   occ : int64 位掩码，bit(x + 8y) == 1 表示该像素是实心的
##   mat : PackedByteArray(64)，下标 y*8+x，0 表示空（与 occ 保持一致）
##
## 材质 id 从 1 开始；occ 是权威数据，mat 是随行的材质表。

const Bits := preload("res://addons/pixel_destruction/core/pixel_bits.gd")

var occ := 0
var mat: PackedByteArray = PackedByteArray()

func _init() -> void:
	mat.resize(Bits.PIXELS)

func clone():
	# 不能在本脚本内用自身类名做类型（没有 class_name），用脚本反射构造。
	var c = get_script().new()
	c.occ = occ
	c.mat = mat.duplicate()
	return c

func is_empty() -> bool:
	return occ == 0

func count() -> int:
	return Bits.popcount(occ)

func get_material(x: int, y: int) -> int:
	if (occ & Bits.bit(x, y)) == 0:
		return 0
	return mat[y * Bits.SIZE + x]

func set_pixel(x: int, y: int, material: int) -> void:
	var b := Bits.bit(x, y)
	occ |= b
	mat[y * Bits.SIZE + x] = material

func clear_pixel(x: int, y: int) -> void:
	occ &= ~Bits.bit(x, y)
	mat[y * Bits.SIZE + x] = 0

func apply_keep_mask(keep: int) -> void:
	## keep 掩码语义与 Teardown 的 remove mask 一致：bit 1 = 保留，0 = 删除。
	## 破坏管线里这就是一次位与 + 一次材质清理。
	var removed := occ & ~keep
	if removed == 0:
		return
	occ &= keep
	while removed != 0:
		var i := Bits.first_bit_index(removed)
		mat[i] = 0
		removed &= removed - 1

func blit_into(target, mask: int) -> void:
	## 把 mask 内的像素复制到 target（split 阶段用）。
	var m := occ & mask
	while m != 0:
		var i := Bits.first_bit_index(m)
		target.occ |= 1 << i
		target.mat[i] = mat[i]
		m &= m - 1

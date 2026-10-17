extends SceneTree
## PhysicsConfig：物理旋钮的**单一真源**闸门。
##
## ⚠️ 为什么必须有它：这个类的价值全在"一处下发、名字对不上要吵闹"，
##    而这两条都**不会**被"代码看起来对"证明：
##      · 默认值搬错了 -> 世界的字段静默变成另一个值（手感变了，没人报错）；
##      · 字段名写错了 -> Object.set() **静默失败**，那个旋钮永远不生效。
##    所以判据全部是"下发之后世界变成什么样"，不是"字段存在"。
const PWorld := preload("res://src/physics/pworld.gd")
const PhysicsConfig := preload("res://src/physics/physics_config.gd")
const AddonWorld := preload("res://src/nodes/pixel_world.gd")

var _pass := 0
var _fail := 0
func _c(n: String, ok: bool, d: String = "") -> void:
	if ok:
		_pass += 1
		print("  PASS  ", n, "  ", d)
	else:
		_fail += 1
		print("  FAIL  ", n, "  ", d)


## 一个"缺字段"的假世界：只有 gravity。
class FakeWorld:
	var gravity := Vector2.ZERO


func _initialize() -> void:
	print("=== PhysicsConfig：旋钮单一真源 ===")
	var cfg := PhysicsConfig.new()
	var names := cfg.knob_names()
	_c("字段清单非空且像模像样", names.size() >= 40, "%d 个字段" % names.size())

	# ---- ① 默认值 = PWorld 现值：下发到全新世界必须**逐位不变** ----
	var w := PWorld.new()
	var before := {}
	var absent := PackedStringArray()
	for n in names:
		if not (n in w):
			absent.append(n)
			continue
		before[n] = w.get(n)
	_c("每个字段在 PWorld 上都能找到（名字没写错）", absent.is_empty(), "缺: %s" % ", ".join(absent))
	var missing := cfg.apply(w)
	_c("apply 报告「全部对得上」", missing.is_empty(), "缺: %s" % ", ".join(missing))
	var moved := PackedStringArray()
	for n in names:
		if before.has(n) and w.get(n) != before[n]:
			moved.append("%s: %s -> %s" % [n, str(before[n]), str(w.get(n))])
	_c("默认值 = PWorld 现值（下发后逐位不变）", moved.is_empty(),
		"动了: %s" % ", ".join(moved.slice(0, 5)))
	var d0 := cfg.diff(w)
	_c("下发之后 diff 为空", d0.is_empty(), ", ".join(d0.slice(0, 5)))

	# ---- ② 下发真的到位：每个字段设成**不同的探针值** ----
	var probe := PhysicsConfig.new()
	for n in names:
		var v: Variant = probe.get(n)
		match typeof(v):
			TYPE_BOOL:
				probe.set(n, not bool(v))
			TYPE_INT:
				probe.set(n, int(v) + 7)
			TYPE_FLOAT:
				probe.set(n, float(v) + 0.25)
			TYPE_VECTOR2:
				probe.set(n, (v as Vector2) + Vector2(3.0, 5.0))
			_:
				_c("探针类型覆盖 %s" % n, false, "type=%d（新增字段类型要在这里补一支）" % typeof(v))
	var w2 := PWorld.new()
	probe.apply(w2)
	var stale := PackedStringArray()
	for n in names:
		if w2.get(n) != probe.get(n):
			stale.append("%s: 世界=%s 配置=%s" % [n, str(w2.get(n)), str(probe.get(n))])
	_c("每个字段都真的下发到了世界", stale.is_empty(), "没到: %s" % ", ".join(stale.slice(0, 5)))

	# ---- ③ capture / apply 往返（"现值快照"真的可用）----
	var snap := PhysicsConfig.new()
	snap.capture(w2)
	var w3 := PWorld.new()
	snap.apply(w3)
	var d3 := snap.diff(w3)
	_c("capture -> apply 往返一致", d3.is_empty(), ", ".join(d3.slice(0, 3)))

	# ---- ④ 字段对不上时**吵闹**（返回缺失名单；push_error 会出现在日志里）----
	var fake := FakeWorld.new()
	var miss2 := cfg.apply(fake)
	_c("缺字段会被列出来（不是静默跳过）",
		miss2.size() == names.size() - 1 and not ("gravity" in miss2),
		"缺 %d / 共 %d" % [miss2.size(), names.size()])
	_c("能对上的那个字段照样下发", fake.gravity == cfg.gravity, str(fake.gravity))

	# ---- ⑤ config 必须覆盖节点旋钮：KNOBS 映射到的世界字段一个都不能漏 ----
	# ⚠️ 漏一个 = 改用 config 下发的场景会**静默丢掉**那个旋钮（节点上设了也没人读）。
	#    这份对照表是**闸门的期望清单**（映射本身在 PixelWorld._push_knob 里）。
	var knobs_world := ["gravity", "fixed_dt", "max_substeps", "sleeping_enabled",
		"terminal_speed", "rp_max_linear_velocity", "max_angular_velocity", "ccd_ignore_mass",
		"min_fragment_pixels", "debris_max_mass", "debris_min_speed",
		"friction_combine_rule", "restitution_combine_rule"]
	var lost := PackedStringArray()
	for n in knobs_world:
		if not (n in names):
			lost.append(n)
	_c("节点 KNOBS 映射到的 %d 个字段都在 config 里" % knobs_world.size(), lost.is_empty(),
		"漏: %s" % ", ".join(lost))

	# ---- ⑥ 消重：节点 @export 的默认值不许与 config 的默认值分叉 ----
	# ⚠️ 节点上的 @export 是"还没换 config 的老场景"那条路的真源。它与 config 分叉
	#    = 同一个旋钮两个默认值（正是这次要消灭的东西），症状是"换了 config 之后手感变了"。
	#    这份对照是**闸门的期望清单**（映射本身在 PixelWorld._push_knob 里）。
	var pw_default = AddonWorld.new()          # 不进场：world == null，不会 push
	var pairs := [["gravity", "gravity"], ["fixed_dt", "fixed_dt"],
		["max_substeps", "max_substeps"], ["sleeping", "sleeping_enabled"],
		["terminal_speed", "terminal_speed"], ["max_linear_velocity", "rp_max_linear_velocity"],
		["max_angular_velocity", "max_angular_velocity"], ["ccd_ignore_mass", "ccd_ignore_mass"],
		["min_fragment_pixels", "min_fragment_pixels"], ["debris_max_mass", "debris_max_mass"],
		["debris_min_speed", "debris_min_speed"],
		["friction_combine_rule", "friction_combine_rule"],
		["restitution_combine_rule", "restitution_combine_rule"]]
	var drift := PackedStringArray()
	for p in pairs:
		var a: Variant = pw_default.get(p[0])
		var b: Variant = cfg.get(p[1])
		if typeof(a) != typeof(b) or a != b:
			drift.append("%s(%s) vs %s(%s)" % [p[0], str(a), p[1], str(b)])
	_c("节点 @export 默认值与 config 默认值一致（%d 项）" % pairs.size(), drift.is_empty(),
		"分叉: %s" % ", ".join(drift))

	# ---- ⑦ 节点层：设了 physics 时配置说了算，旧 @export 不再覆盖它 ----
	var pw = AddonWorld.new()
	get_root().add_child(pw)
	await process_frame
	var ncfg := PhysicsConfig.new()
	ncfg.gravity = Vector2(1.0, -2.0)
	ncfg.max_substeps = 9
	ncfg.debris_max_mass = 33.0
	pw.physics = ncfg                       # setter 契约：改了立刻播
	_c("节点层：设了 physics 立刻生效（setter 契约）",
		pw.world.gravity == Vector2(1.0, -2.0) and pw.world.max_substeps == 9
			and pw.world.debris_max_mass == 33.0,
		"g=%s sub=%d debris=%.0f" % [str(pw.world.gravity), pw.world.max_substeps, pw.world.debris_max_mass])
	# 故意在节点上设一个不同的值，再 push：配置必须赢 —— 否则"关卡里残留的一行旧值"
	# 会静默压掉配置，而配置存在的意义正是收口。
	pw.gravity = Vector2(100.0, 100.0)
	pw.max_substeps = 77
	pw.push_physics_settings()
	_c("节点层：push 之后配置仍然说了算（旧 @export 不覆盖它）",
		pw.world.gravity == Vector2(1.0, -2.0) and pw.world.max_substeps == 9,
		"g=%s sub=%d" % [str(pw.world.gravity), pw.world.max_substeps])

	# ---- ⑧ 没设 physics：老路照旧（老关卡不炸）----
	var pw2 = AddonWorld.new()
	get_root().add_child(pw2)
	await process_frame
	pw2.gravity = Vector2(7.0, 8.0)
	pw2.max_substeps = 6
	pw2.push_physics_settings()
	_c("节点层：没设 physics 时 @export 照旧生效",
		pw2.world.gravity == Vector2(7.0, 8.0) and pw2.world.max_substeps == 6,
		"g=%s sub=%d" % [str(pw2.world.gravity), pw2.world.max_substeps])

	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

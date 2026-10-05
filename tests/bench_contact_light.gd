extends SceneTree
## 接触事件成本 + 抓取子步成本的标定探针（诊断用，不是自检测试）。
##
## 量三件事：
##   1. 接触事件的三种用法：关 / 开 / 开+轻量模式（contact_stress_enabled=false）
##      -> 每子步、每接触多少 us（"接触事件轻量模式"的收益）
##   2. 接触宽度惰性化之后还剩多少（轻量模式与"关事件"的差 = 协议 + 对象分配）
##   3. 每矩形每子步的成本（ccd_grab_substep_cost_budget_us / CCD_RECT_COST_US 的标定依据）
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

var _sink := 0.0

func _ground(w: PWorld, width: int) -> void:
	var g := PBody.new()
	g.position = Vector2(-width / 2, 300)
	g.make_static()
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, width, 40), 1)
	w.add_body(g, [s])

## 一摞落在同一地面上的方块：N 个 -> 大量接触对
## mode: 0=关事件  1=开事件+应力  2=开事件+轻量模式  3=轻量模式+消费者读 contact_width
func _pile(n: int, mode: int, ground_w: int) -> PWorld:
	var w := PWorld.new()
	w.gravity = Vector2(0, 400)
	w.contact_events_enabled = mode != 0
	w.contact_stress_enabled = mode == 1
	# ⚠️ 必须配材质强度：不配的话 shear_ratio 那一段（两次 thickness_at）根本不跑，
	#    轻量模式就"省了个寂寞"—— 实测两种模式在这种场景里一模一样。
	w.set_material_strength(1, 100.0, 30.0)
	_ground(w, ground_w)
	for i in n:
		var b := PBody.new()
		b.position = Vector2(-200 + (i % 25) * 16, -200 - (i / 25) * 16)
		var bs := PixelShape.new()
		bs.fill_rect(Rect2i(0, 0, 12, 12), 1)
		w.add_body(b, [bs])
	return w

func _time_pile(n: int, mode: int, ground_w: int, steps: int) -> Dictionary:
	var best := {}
	var best_ms := 1.0e9
	for rep in 2:
		var w := _pile(n, mode, ground_w)
		for i in 40:
			w.step(1.0 / 60.0)
		var subs := 0
		var cons := 0
		var sink := 0.0
		var t0 := Time.get_ticks_usec()
		for i in steps:
			w.step(1.0 / 60.0)
			subs += w.last_substeps
			cons += w.contacts.size()
			if mode == 3:
				for c in w.contacts:
					sink += c.contact_width
		_sink = sink
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / float(steps)
		if ms < best_ms:
			best_ms = ms
			best = {"ms": ms, "subs": float(subs) / float(steps), "cons": float(cons) / float(steps)}
	return best

func _rect_world(total: int, dyn: int) -> PWorld:
	var w := PWorld.new()
	w.gravity = Vector2(0, 400)
	_ground(w, 600)
	var big := PBody.new()
	big.position = Vector2(0, 0)
	big.make_static()
	var bs := PixelShape.new()
	# 每行 20 个**互不相邻**的 2x1 矩形：贪心合并不掉它们，矩形数才可控
	var rows := maxi(0, (total - dyn - 1 + 19) / 20)
	for j in rows:
		for k in 20:
			bs.fill_rect(Rect2i(-600 + k * 4, 600 + j * 3, 2, 1), 1)
	w.add_body(big, [bs])
	for i in dyn:
		var b := PBody.new()
		b.position = Vector2(-200 + (i % 25) * 16, -200 - (i / 25) * 16)
		var s := PixelShape.new()
		s.fill_rect(Rect2i(0, 0, 12, 12), 1)
		w.add_body(b, [s])
	return w

func _time_rects(total: int, dyn: int, steps: int) -> Dictionary:
	var best := 1.0e9
	var rects := 0
	var subs_avg := 0.0
	for rep in 2:
		var w := _rect_world(total, dyn)
		rects = 0
		for b in w.bodies:
			rects += b.rects.size()
		for i in 30:
			w.step(1.0 / 60.0)
		var subs := 0
		var t0 := Time.get_ticks_usec()
		for i in steps:
			w.step(1.0 / 60.0)
			subs += w.last_substeps
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / float(steps)
		if ms < best:
			best = ms
			subs_avg = float(subs) / float(steps)
	var per := best * 1000.0 / maxf(0.001, subs_avg)
	return {"ms": best, "rects": rects, "subs": subs_avg, "us_per_sub": per}

## 取一对接触的**纯协议**成本：同一个世界、同一批接触对，反复调 contact_info。
## force_two = true 时把猜值改成 1（必然不够）-> 逼它走"两步式"，差值就是一次 _rp_send。
func _fetch_cost(n: int, ground_w: int, reps: int, force_two: bool) -> float:
	var w := _pile(n, 2, ground_w)
	# ⚠️ 要等它们真的落在地上：40 步时还在半空 -> 接触对 0（第一次跑就是这么拿到 0.000 的）
	for i in 120:
		w.step(1.0 / 60.0)
	var pairs := w.contact_pair_count()
	if pairs <= 0:
		return 0.0
	var sink := 0
	var t0 := Time.get_ticks_usec()
	for r in reps:
		for i in pairs:
			if force_two:
				w._contact_point_hint.resize(i + 1)
				w._contact_point_hint[i] = 1
			var info: Dictionary = w.contact_info(i)
			sink += info["points"].size()
	_sink += float(sink)
	return float(Time.get_ticks_usec() - t0) / float(reps) / float(pairs)


func _initialize() -> void:
	await process_frame
	print("=== 1. 接触事件的四种用法（材质强度已配；40 步热身 + 计时，min-of-2）===")
	for cfg in [[120, 400], [240, 400]]:
		var n: int = cfg[0]
		var gw: int = cfg[1]
		var off := _time_pile(n, 0, gw, 120)
		var on := _time_pile(n, 1, gw, 120)
		var light := _time_pile(n, 2, gw, 120)
		var read := _time_pile(n, 3, gw, 120)
		print("  %4d 体/地面%d: 关事件 %7.3f ms/步 (%.1f 子步, %.1f 接触/步)"
			% [n, gw, off["ms"], off["subs"], on["cons"]])
		print("                 开+应力 %7.3f | 轻量 %7.3f | 轻量+读宽度 %7.3f"
			% [on["ms"], light["ms"], read["ms"]])
		print("                 us/接触: 应力 %6.1f | 轻量 %6.1f | 轻量+读宽度 %6.1f"
			% [(on["ms"] - off["ms"]) * 1000.0 / maxf(0.001, on["cons"]),
			   (light["ms"] - off["ms"]) * 1000.0 / maxf(0.001, light["cons"]),
			   (read["ms"] - off["ms"]) * 1000.0 / maxf(0.001, read["cons"])])
	print("=== 1b. 取一对接触的协议成本：一次调用 vs 两步式（op 35 的 cap 猜值）===")
	for cfg in [[120, 400], [240, 400]]:
		var n: int = cfg[0]
		var gw: int = cfg[1]
		var one := _fetch_cost(n, gw, 60, false)
		var two := _fetch_cost(n, gw, 60, true)
		print("  %4d 体: 猜值命中 %6.3f us/对 | 逼成两步 %6.3f us/对 -> 一次 _rp_send = %.3f us"
			% [n, one, two, maxf(0.0, two - one)])
	print("=== 2. 每矩形每子步成本（抓取预算的标定）===")
	var prev_n := 0
	var prev_us := 0.0
	for total in [500, 1000, 2000, 4000]:
		var r := _time_rects(total, 25, 60)
		var marg := "     -"
		if prev_n > 0:
			marg = "%5.2f us/矩形（边际）" % ((r["us_per_sub"] - prev_us) / float(r["rects"] - prev_n))
		print("  矩形 %5d: %7.3f ms/步, %.2f 子步/步 -> %7.1f us/子步   均摊 %5.2f   %s"
			% [r["rects"], r["ms"], r["subs"], r["us_per_sub"],
			   r["us_per_sub"] / maxf(1.0, float(r["rects"])), marg])
		prev_n = r["rects"]
		prev_us = r["us_per_sub"]
	quit(0)
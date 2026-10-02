// collide 的 C++ 移植 —— 目标不是"差不多"，是**逐位一致**。
//
// 关键难点：GDScript 里 @@Vector2@@ 是 float32，而裸 float 是 float64。
// 所以：
//   · 凡是 Vector2 的运算（加减乘、点积、length、normalized、lerp）一律用 float
//   · 凡是 GDScript 里裸 float 的运算（sep、ra+rb、d1-d2、裁剪参数）一律用 double
//   · 点积必须返回 float32（Godot 的 Vector2::dot 返回 real_t）
// 另外必须关掉编译器的浮点收缩（-ffp-contract=off），否则 a*b+c*d 会被合成 FMA，结果就不同了。
#pragma once
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>

namespace phys {

// 字节缓冲读写（不依赖对齐，用 memcpy 让编译器优化成单条 mov）
static inline double rd_f64(const uint8_t *p) { double d; std::memcpy(&d, p, 8); return d; }
static inline void wr_f64(uint8_t *p, double d) { std::memcpy(p, &d, 8); }
static inline void wr_i32(uint8_t *p, int32_t v) { std::memcpy(p, &v, 4); }

struct V2 { float x, y; };

static inline V2 v2(float x, float y) { return V2{ x, y }; }
static inline V2 vadd(V2 a, V2 b) { return V2{ a.x + b.x, a.y + b.y }; }
static inline V2 vsub(V2 a, V2 b) { return V2{ a.x - b.x, a.y - b.y }; }
static inline V2 vmul(V2 a, float s) { return V2{ a.x * s, a.y * s }; }
static inline V2 vneg(V2 a) { return V2{ -a.x, -a.y }; }

// Vector2::dot 返回 real_t = float32
static inline float vdot(V2 a, V2 b) { return a.x * b.x + a.y * b.y; }

// Vector2::length
static inline float vlen(V2 a) { return std::sqrt(a.x * a.x + a.y * a.y); }

// Vector2::normalized
static inline V2 vnormalized(V2 a) {
	float l = vlen(a);
	if (l == 0.0f) { return V2{ 0.0f, 0.0f }; }
	return V2{ a.x / l, a.y / l };
}

// Vector2::lerp —— Godot 是 x + (p_weight * (to.x - x))，乘法顺序要一致
static inline V2 vlerp(V2 a, V2 b, float t) {
	V2 r = a;
	r.x += t * (b.x - a.x);
	r.y += t * (b.y - a.y);
	return r;
}

struct OBB { V2 center, u, v, h; };

static inline V2 obb_vertex(const OBB &o, int i) {
	switch (i) {
		case 0: return vsub(vsub(o.center, vmul(o.u, o.h.x)), vmul(o.v, o.h.y));
		// center + u*h.x - v*h.y —— 注意是 ((center + u*hx) - v*hy)，与 GDScript 的从左到右一致
		case 1: return vsub(vadd(o.center, vmul(o.u, o.h.x)), vmul(o.v, o.h.y));
		case 2: return vadd(vadd(o.center, vmul(o.u, o.h.x)), vmul(o.v, o.h.y));
		default: return vadd(vsub(o.center, vmul(o.u, o.h.x)), vmul(o.v, o.h.y));
	}
}

static inline V2 obb_edge_normal(const OBB &o, int i) {
	switch (i) {
		case 0: return vneg(o.v);
		case 1: return o.u;
		case 2: return o.v;
		default: return vneg(o.u);
	}
}

// absf(u.dot(axis)) * h.x + absf(v.dot(axis)) * h.y
// 点积是 float32，abs 与乘加是 float64
static inline double obb_project_radius(const OBB &o, V2 axis) {
	return std::fabs((double)vdot(o.u, axis)) * (double)o.h.x
		 + std::fabs((double)vdot(o.v, axis)) * (double)o.h.y;
}

struct Sat { double sep; V2 normal; bool from_a; };

static inline void sat_signed_into(const OBB &a, const OBB &b, Sat &out) {
	V2 axes[4] = { a.u, a.v, b.u, b.v };
	double best_sep = -INFINITY;
	V2 best_axis = v2(1.0f, 0.0f);
	bool best_from_a = true;
	V2 dc = vsub(b.center, a.center);
	for (int i = 0; i < 4; ++i) {
		V2 axis = axes[i];
		double ra = obb_project_radius(a, axis);
		double rb = obb_project_radius(b, axis);
		double d = (double)vdot(dc, axis);
		double sep = std::fabs(d) - (ra + rb);
		if (sep > best_sep) {
			best_sep = sep;
			best_axis = (d >= 0.0) ? axis : vneg(axis);
			best_from_a = (i < 2);
		}
	}
	out.sep = best_sep;
	out.normal = best_axis;
	out.from_a = best_from_a;
}

static inline V2 obb_support(const OBB &o, V2 dir) {
	V2 p = o.center;
	double s1 = (vdot(o.u, dir) >= 0.0f) ? (double)o.h.x : -(double)o.h.x;
	p = vadd(p, vmul(o.u, (float)s1));
	double s2 = (vdot(o.v, dir) >= 0.0f) ? (double)o.h.y : -(double)o.h.y;
	p = vadd(p, vmul(o.v, (float)s2));
	return p;
}

// _clip_segment：保留 dot(n, p) <= offset 的部分
static inline int clip_segment(V2 p1, V2 p2, V2 n, double offset, V2 out[2]) {
	double d1 = (double)vdot(n, p1) - offset;
	double d2 = (double)vdot(n, p2) - offset;
	if (d1 <= 0.0 && d2 <= 0.0) { out[0] = p1; out[1] = p2; return 2; }
	if (d1 > 0.0 && d2 > 0.0) { return 0; }
	if (d1 > 0.0) {
		double t = d1 / (d1 - d2);
		out[0] = vlerp(p1, p2, (float)t);
		out[1] = p2;
		return 2;
	}
	double t2 = d2 / (d2 - d1);
	out[0] = p1;
	out[1] = vlerp(p1, p2, (float)t2);
	return 2;
}

// 推测接触（sep > 0）的接触点。**必须与 collide.gd 的 speculative_point 逐位等价**。
// ⚠️ 这里刻意用"两个支撑点的中点"这个不精确公式，理由写在 collide.gd 那一侧：
// 更正确的点会让推测接触真正起作用，而引擎的全部调参建立在"它是死的"之上
// （实测改正确后 sleep_box 0/12 → 10/12、test_parallel 陷地 5250 px）。
// 曾经因为 GDScript 改了而这里没改，两条路径的接触点差出 3.88 个单位。
//
// ⚠️ 不要写成两个支撑点的中点：obb_support() 返回的是**角点**，两盒切向跨度差很多时
// （小箱子 vs 半宽 2000 的地面）中点会被拉到远离真实接触区的地方（实测上千单位），
// 力臂错成那样 → 接触法向质量趋近 0 —— **推测接触实际上是失效的**。
//
// 正确做法：取 A 朝 B 的支撑点，再把它的切向坐标夹进 B 的切向范围。
// 这个修复会激活长期休眠的机制，必须连同边际一起调参（见开发日志坑 34）。
static inline V2 speculative_point(const OBB &a, const OBB &b, V2 n) {
	V2 pa = obb_support(a, n);
	V2 pb = obb_support(b, vneg(n));
	return vmul(vadd(pa, pb), 0.5f);
}

struct Pt { double px, py, depth, sep, feature; };
struct Result { V2 normal; int count; Pt pts[2]; };

static inline void collide(const OBB &a, const OBB &b, double margin, Sat &s, Result &out) {
	sat_signed_into(a, b, s);
	double sep = s.sep;
	// _NO_CONTACT 的 normal 是 Vector2.RIGHT
	if (sep > margin) { out.normal = v2(1.0f, 0.0f); out.count = 0; return; }
	V2 normal = s.normal;
	if (sep > 0.0) {
		// ⚠️ 这里曾经内联着**旧公式**（两个支撑点的中点），而上面刚写好的
		// speculative_point 没人调用 —— 结果 GDScript 侧改了、C++ 侧没改，
		// 两条路径的推测接触点差出 3.88 个单位（实测 3610 个流形里 115 个不同，
		// 法向/深度/分离度全对，只有点位错）。
		// **同一规则写在两个地方就一定会分叉**，所以这里只留一次调用。
		V2 pos = speculative_point(a, b, normal);
		out.normal = normal;
		out.count = 1;
		out.pts[0] = Pt{ (double)pos.x, (double)pos.y, 0.0, sep, -1.0 };
		return;
	}
	// 边界：sep 恰好为 0（面贴面）时旧代码会提前返回 hit=false，**必须原样保留**
	if (sep >= 0.0) { out.normal = v2(1.0f, 0.0f); out.count = 0; return; }

	bool from_a = s.from_a;
	const OBB &ref = from_a ? a : b;
	const OBB &inc = from_a ? b : a;
	V2 ref_normal = from_a ? normal : vneg(normal);

	int ref_edge = 0;
	double best_dot = -INFINITY;
	for (int i = 0; i < 4; ++i) {
		double d = (double)vdot(obb_edge_normal(ref, i), ref_normal);
		if (d > best_dot) { best_dot = d; ref_edge = i; }
	}
	int inc_edge = 0;
	double worst_dot = INFINITY;
	for (int i = 0; i < 4; ++i) {
		double d2 = (double)vdot(obb_edge_normal(inc, i), ref_normal);
		if (d2 < worst_dot) { worst_dot = d2; inc_edge = i; }
	}

	V2 rp1 = obb_vertex(ref, ref_edge);
	V2 rp2 = obb_vertex(ref, (ref_edge + 1) % 4);
	V2 ip1 = obb_vertex(inc, inc_edge);
	V2 ip2 = obb_vertex(inc, (inc_edge + 1) % 4);

	V2 tangent = vnormalized(vsub(rp2, rp1));
	V2 seg[2];
	if (clip_segment(ip1, ip2, vneg(tangent), -(double)vdot(tangent, rp1), seg) == 0) {
		out.normal = normal; out.count = 0; return;
	}
	V2 seg2[2];
	if (clip_segment(seg[0], seg[1], tangent, (double)vdot(tangent, rp2), seg2) == 0) {
		out.normal = normal; out.count = 0; return;
	}

	int base = ref_edge * 16 + inc_edge * 4;
	out.normal = normal;
	out.count = 0;
	for (int i = 0; i < 2; ++i) {
		V2 p = seg2[i];
		double separation = (double)vdot(vsub(p, rp1), ref_normal);
		if (separation <= 0.0) {
			out.pts[out.count] = Pt{ (double)p.x, (double)p.y, -separation, separation, (double)(base + i) };
			out.count++;
		}
	}
}

} // namespace phys

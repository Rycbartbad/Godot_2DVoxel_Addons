// 求解器的 C++ 移植（顺序冲量 + 块求解器 + warm start + split impulse）。
//
// 逐位等价的纪律与 collide/broadphase 相同：
//   · Vector2 的一切都是 float32；GDScript 的裸 float（冲量、有效质量、偏置）是 float64
//   · Godot 的 Vector2 * real_t 会**先把标量截成 float32 再相乘** —— 所以
//     impulse * inv_mass 里的 inv_mass（double）必须先 (float) 转换
//   · Vector2::cross / dot 返回 real_t = float32
//   · 迭代顺序 = 10 轮 x 按数组顺序。这与"按岛并行"逐位相同：
//     岛之间不共享动态体，所以全局顺序循环在每个岛内的子序列就是岛内顺序。
#pragma once
#include "collide_kernel.h"
#include <unordered_map>
#include <vector>
#include <algorithm>

namespace phys {

static const int SV_HDR = 96;
static const int SV_BODY = 96;
static const int SV_MAN = 120;    // 直接复用宽相的流形记录
static const int SV_OUT = 48;     // 每体：vel.xy / w / pvel.xy / pw
static const int SV_GRAB = 48;    // 每抓取：body_index / r.xy / bias.xy / max_impulse

static inline int64_t sv_make_key(int32_t ia, int32_t ra, int32_t ib, int32_t rb) {
	return ((int64_t)(ia & 0xFFFF) << 48) | ((int64_t)(ra & 0xFF) << 40)
		| ((int64_t)(ib & 0xFFFF) << 24) | ((int64_t)(rb & 0xFF) << 16);
}

struct SvBody {
	V2 com;
	double inv_mass, inv_inertia;
	V2 vel; double w;
	V2 pvel; double pw;
	int32_t awake, is_static, id;
};

struct SvPt {
	V2 pos;
	double sep;
	int32_t feature;
	V2 ra, rb;
	double rn_a, rn_b, rt_a, rt_b;
	double kn, normal_mass, tangent_mass;
	double vbias, pbias;
	double ni, ti, pni;
};

struct SvMan {
	int32_t ia, ib, count;
	V2 n, t;
	double mu;
	double ma, mb, ia_, ib_;
	bool wa, wb;
	double k12;
	bool two;
	int64_t key;
	SvPt pts[2];
};

struct WarmEntry { int32_t feat[2]; double ni[2], ti[2]; int32_t count; };



struct SvParams {
	int32_t n_bodies, n_mans, iterations, use_block;
	double dt, baumgarte, slop, max_dep, rest_thresh, g_rest, g_fric, m_fric, m_rest;
	int32_t n_grabs;
};

// 抓取约束（鼠标关节）。只在求解期间使用的量全部由 GDScript 预先算好 ——
// 求解本身只改速度、不改位姿，所以 anchor / r / bias 在 10 次迭代里是常量。
struct SvGrab {
	int32_t ib;
	V2 r;        // anchor - com（float32）
	V2 bias;     // 期望速度（float32）
	double max_imp;
};

static inline SvParams sv_read_params(const uint8_t *h) {
	SvParams p;
	p.n_bodies = rd_i32b(h + 0);
	p.n_mans = rd_i32b(h + 4);
	p.iterations = rd_i32b(h + 8);
	p.use_block = rd_i32b(h + 12);
	p.dt = rd_f64(h + 16);
	p.baumgarte = rd_f64(h + 24);
	p.slop = rd_f64(h + 32);
	p.max_dep = rd_f64(h + 40);
	p.rest_thresh = rd_f64(h + 48);
	p.g_rest = rd_f64(h + 56);
	p.g_fric = rd_f64(h + 64);
	p.m_fric = rd_f64(h + 72);
	p.m_rest = rd_f64(h + 80);
	p.n_grabs = rd_i32b(h + 88);
	return p;
}

static inline void sv_load_body(const uint8_t *p, SvBody &b) {
	b.com = V2{ (float)rd_f64(p + 0), (float)rd_f64(p + 8) };
	b.inv_mass = rd_f64(p + 16);
	b.inv_inertia = rd_f64(p + 24);
	b.vel = V2{ (float)rd_f64(p + 32), (float)rd_f64(p + 40) };
	b.w = rd_f64(p + 48);
	b.pvel = V2{ (float)rd_f64(p + 56), (float)rd_f64(p + 64) };
	b.pw = rd_f64(p + 72);
	b.awake = rd_i32b(p + 80);
	b.is_static = rd_i32b(p + 84);
	b.id = rd_i32b(p + 88);
}

// 速度采样：lv + Vector2(-w*r.y, w*r.x)，中间量按 float32 落地
// ⚠️ **Vector2 * real_t 是"先把标量截成 float32，再在 float32 里相乘"**。
// 写成 (float)((double)v.x * s) 会先用 double 乘、最后才舍入 —— 差 1 个 float32 ULP，
// 在病态的 2x2 LCP 里被放大成可见偏差。这条规则写在文件头上，但乘法里必须逐处照做。
static inline V2 sv_scale(V2 v, double s) {
	float f = (float)s;
	return V2{ v.x * f, v.y * f };
}

static inline V2 sv_vel_at(const SvBody &b, V2 r) {
	float x = (float)(-(b.w * (double)r.y));
	float y = (float)(b.w * (double)r.x);
	return V2{ b.vel.x + x, b.vel.y + y };
}
static inline V2 sv_pvel_at(const SvBody &b, V2 r) {
	float x = (float)(-(b.pw * (double)r.y));
	float y = (float)(b.pw * (double)r.x);
	return V2{ b.pvel.x + x, b.pvel.y + y };
}
// r x impulse（Vector2::cross 返回 float32）
static inline float sv_cross(V2 r, V2 imp) { return r.x * imp.y - r.y * imp.x; }

struct SvState { SvBody *a; SvBody *b; SvMan *m; };

static inline void sv_apply(SvBody &a, SvBody &b, SvMan &m, int pi, V2 imp) {
	if (imp.x == 0.0f && imp.y == 0.0f) return;
	if (m.wa) {
		float s = (float)a.inv_mass;
		a.vel.x -= imp.x * s;
		a.vel.y -= imp.y * s;
		a.w -= a.inv_inertia * (double)sv_cross(m.pts[pi].ra, imp);
	}
	if (m.wb) {
		float s = (float)b.inv_mass;
		b.vel.x += imp.x * s;
		b.vel.y += imp.y * s;
		b.w += b.inv_inertia * (double)sv_cross(m.pts[pi].rb, imp);
	}
}

static inline void sv_apply_pseudo(SvBody &a, SvBody &b, SvMan &m, int pi, V2 imp) {
	if (imp.x == 0.0f && imp.y == 0.0f) return;
	if (m.wa) {
		float s = (float)a.inv_mass;
		a.pvel.x -= imp.x * s;
		a.pvel.y -= imp.y * s;
		a.pw -= a.inv_inertia * (double)sv_cross(m.pts[pi].ra, imp);
	}
	if (m.wb) {
		float s = (float)b.inv_mass;
		b.pvel.x += imp.x * s;
		b.pvel.y += imp.y * s;
		b.pw += b.inv_inertia * (double)sv_cross(m.pts[pi].rb, imp);
	}
}

// 2 点法向块求解器
static inline void sv_block(SvMan &m, SvBody &a, SvBody &b) {
	SvPt &p1 = m.pts[0];
	SvPt &p2 = m.pts[1];
	double k11 = p1.kn, k22 = p2.kn, k12 = m.k12;
	V2 n = m.n;
	V2 vb1 = sv_vel_at(b, p1.rb), va1 = sv_vel_at(a, p1.ra);
	V2 vb2 = sv_vel_at(b, p2.rb), va2 = sv_vel_at(a, p2.ra);
	double vn1 = (double)vdot(V2{ vb1.x - va1.x, vb1.y - va1.y }, n);
	double vn2 = (double)vdot(V2{ vb2.x - va2.x, vb2.y - va2.y }, n);
	double rhs1 = p1.vbias - vn1;
	double rhs2 = p2.vbias - vn2;
	double x1 = p1.ni, x2 = p2.ni;
	double dx1 = 0.0, dx2 = 0.0;
	bool solved = false;
	double det = k11 * k22 - k12 * k12;
	if (std::fabs(det) > 1e-12) {
		dx1 = (k22 * rhs1 - k12 * rhs2) / det;
		dx2 = (k11 * rhs2 - k12 * rhs1) / det;
		if (x1 + dx1 >= 0.0 && x2 + dx2 >= 0.0) solved = true;
	}
	if (!solved && k22 > 1e-12) {
		double d2 = rhs2 / k22;
		if (x2 + d2 >= 0.0 && k12 * (x2 + d2) - rhs1 >= -1e-9) { dx1 = -x1; dx2 = d2; solved = true; }
	}
	if (!solved && k11 > 1e-12) {
		double d1 = rhs1 / k11;
		if (x1 + d1 >= 0.0 && k12 * (x1 + d1) - rhs2 >= -1e-9) { dx1 = d1; dx2 = -x2; solved = true; }
	}
	if (!solved) {
		if (rhs1 <= 0.0 && rhs2 <= 0.0) { dx1 = -x1; dx2 = -x2; }
		else return;
	}
	p1.ni = x1 + dx1;
	p2.ni = x2 + dx2;
	sv_apply(a, b, m, 0, sv_scale(n, dx1));
	sv_apply(a, b, m, 1, sv_scale(n, dx2));
}

static inline void sv_solve_manifold(SvMan &m, SvBody &a, SvBody &b, const SvParams &P) {
	V2 n = m.n, tangent = m.t;
	double mu = m.mu;
	bool block = (P.use_block != 0) && m.two;
	if (block) sv_block(m, a, b);
	for (int i = 0; i < m.count; ++i) {
		SvPt &p = m.pts[i];
		if (!block) {
			V2 vb = sv_vel_at(b, p.rb);
			V2 va = sv_vel_at(a, p.ra);
			double vn = (double)vdot(V2{ vb.x - va.x, vb.y - va.y }, n);
			double dl = p.normal_mass * (p.vbias - vn);
			double new_n = std::max(p.ni + dl, 0.0);
			dl = new_n - p.ni;
			p.ni = new_n;
			V2 imp = sv_scale(n, dl);
			if (imp.x != 0.0f || imp.y != 0.0f) sv_apply(a, b, m, i, imp);
		}
		if (p.pbias > 0.0 && p.normal_mass > 0.0) {
			V2 pvb = sv_pvel_at(b, p.rb);
			V2 pva = sv_pvel_at(a, p.ra);
			double pvn = (double)vdot(V2{ pvb.x - pva.x, pvb.y - pva.y }, n);
			double pdl = p.normal_mass * (p.pbias - pvn);
			double pnew = std::max(p.pni + pdl, 0.0);
			pdl = pnew - p.pni;
			p.pni = pnew;
			V2 imp = sv_scale(n, pdl);
			if (imp.x != 0.0f || imp.y != 0.0f) sv_apply_pseudo(a, b, m, i, imp);
		}
		V2 vb2 = sv_vel_at(b, p.rb);
		V2 va2 = sv_vel_at(a, p.ra);
		double vt = (double)vdot(V2{ vb2.x - va2.x, vb2.y - va2.y }, tangent);
		double dt_imp = -p.tangent_mass * vt;
		double max_f = mu * p.ni;
		double new_t = std::min(std::max(p.ti + dt_imp, -max_f), max_f);
		dt_imp = new_t - p.ti;
		p.ti = new_t;
		V2 imp = sv_scale(tangent, dt_imp);
		if (imp.x != 0.0f || imp.y != 0.0f) sv_apply(a, b, m, i, imp);
	}
}

static inline void sv_load_grab(const uint8_t *p, SvGrab &g) {
	g.ib = rd_i32b(p + 0);
	g.r = V2{ (float)rd_f64(p + 8), (float)rd_f64(p + 16) };
	g.bias = V2{ (float)rd_f64(p + 24), (float)rd_f64(p + 32) };
	g.max_imp = rd_f64(p + 40);
}

// 逐字复刻 Grab.solve 的迭代部分。
// ⚠️ 精度规则与前文一致：r / bias / rhs 都是 **float32**（它们是 Vector2 分量），
// k11/k12/k22/det/lx/ly/max_impulse 是 double，
// 而 @@next.normalized() * max_impulse@@ 又是"先截成 float32 再乘"。
static inline void sv_solve_grab(SvBody &b, const SvGrab &g, float &acc_x, float &acc_y) {
	if (b.is_static) return;                 // Grab.solve 开头的 is_static 判断
	V2 r = g.r;
	V2 v = sv_vel_at(b, r);
	// ⚠️ 这里**必须用 double**：GDScript 的 bias.x / v.x 虽然都是 Vector2 分量（float32），
	// 但读出来会提升成 double 再相减 —— 结果是**精确的 double 差值**，不是 float32。
	// 写成 float 会多一次舍入，而这里 det ~ 1e-7、len 又恰好卡在限力阈值上，
	// 1 ULP 就会让"是否限力"翻面（实测差 2.44e-4）。
	double rhs_x = (double)g.bias.x - (double)v.x;
	double rhs_y = (double)g.bias.y - (double)v.y;
	double im = b.inv_mass, ii = b.inv_inertia;
	double rx = (double)r.x, ry = (double)r.y;
	double k11 = im + ii * ry * ry;
	double k12 = -ii * rx * ry;
	double k22 = im + ii * rx * rx;
	double det = k11 * k22 - k12 * k12;
	if (!(det >= 1e-12)) return;             // GDScript 是 if det < 1e-12: return
	float lx = (float)((k22 * rhs_x - k12 * rhs_y) / det);    // Vector2(lx, ly) 截成 float32
	float ly = (float)((k11 * rhs_y - k12 * rhs_x) / det);
	// next := accumulated + Vector2(lx, ly)  —— Vector2 构造会把它们截成 float32
	float nx = acc_x + lx;
	float ny = acc_y + ly;
	if (g.max_imp > 0.0) {
		float lensq = nx * nx + ny * ny;
		float len = std::sqrt(lensq);
		if ((double)len > g.max_imp) {
			float f = (float)g.max_imp;
			if (lensq == 0.0f) { nx = 0.0f; ny = 0.0f; }   // normalized() 的零长度分支
			else { nx = (nx / len) * f; ny = (ny / len) * f; }
		}
	}
	float dx = nx - acc_x;
	float dy = ny - acc_y;
	acc_x = nx;
	acc_y = ny;
	// b.apply_impulse(delta, anchor)
	if (b.inv_mass <= 0.0) return;
	float s = (float)b.inv_mass;
	b.vel.x += dx * s;
	b.vel.y += dy * s;
	b.w += b.inv_inertia * (double)sv_cross(r, V2{ dx, dy });
}


static inline void sv_run(const uint8_t *bod, const uint8_t *mans, uint8_t *out,
		std::unordered_map<int64_t, WarmEntry> &warm) {
	SvParams P = sv_read_params(bod);
	int32_t n = P.n_bodies;
	int32_t nm = P.n_mans;
	std::vector<SvBody> bodies(n);
	for (int32_t i = 0; i < n; ++i) sv_load_body(bod + SV_HDR + i * SV_BODY, bodies[i]);

	// 抓取表跟在物体表之后
	int32_t ng = P.n_grabs;
	std::vector<SvGrab> grabs(ng > 0 ? ng : 0);
	std::vector<float> gacc((ng > 0 ? ng : 0) * 2, 0.0f);   // 累积冲量，每子步从 0 开始
	const uint8_t *grab_base = bod + SV_HDR + n * SV_BODY;
	for (int32_t i = 0; i < ng; ++i) sv_load_grab(grab_base + i * SV_GRAB, grabs[i]);

	std::vector<SvMan> ms(nm);
	for (int32_t k = 0; k < nm; ++k) {
		const uint8_t *r = mans + 8 + k * SV_MAN;   // 宽相输出带 8 字节头
		SvMan &m = ms[k];
		m.ia = rd_i32b(r + 0);
		m.ib = rd_i32b(r + 4);
		int32_t ra = rd_i32b(r + 8), rb = rd_i32b(r + 12);
		m.n = V2{ (float)rd_f64(r + 16), (float)rd_f64(r + 24) };
		m.count = rd_i32b(r + 32);
		if (m.count > 2) m.count = 2;
		m.key = sv_make_key(bodies[m.ia].id, ra, bodies[m.ib].id, rb);
		double e = std::max(P.m_rest, P.g_rest);
		m.mu = std::max(P.m_fric, P.g_fric);
		SvBody &a = bodies[m.ia];
		SvBody &b = bodies[m.ib];
		m.t = V2{ -m.n.y, m.n.x };
		m.wa = (a.awake != 0 && a.is_static == 0);
		m.wb = (b.awake != 0 && b.is_static == 0);
		m.ia_ = m.wa ? a.inv_inertia : 0.0;
		m.ib_ = m.wb ? b.inv_inertia : 0.0;
		m.ma = m.wa ? a.inv_mass : 0.0;
		m.mb = m.wb ? b.inv_mass : 0.0;
		m.two = (m.count == 2);
		WarmEntry *we = nullptr;
		auto it = warm.find(m.key);
		if (it != warm.end()) we = &it->second;
		for (int i = 0; i < m.count; ++i) {
			const uint8_t *pr = r + 40 + i * 40;
			SvPt &p = m.pts[i];
			p.pos = V2{ (float)rd_f64(pr + 0), (float)rd_f64(pr + 8) };
			p.sep = rd_f64(pr + 24);
			p.feature = (int32_t)rd_f64(pr + 32);
			p.ra = V2{ p.pos.x - a.com.x, p.pos.y - a.com.y };
			p.rb = V2{ p.pos.x - b.com.x, p.pos.y - b.com.y };
			p.rn_a = (double)sv_cross(p.ra, m.n);
			p.rn_b = (double)sv_cross(p.rb, m.n);
			p.kn = m.ma + m.mb + m.ia_ * p.rn_a * p.rn_a + m.ib_ * p.rn_b * p.rn_b;
			p.normal_mass = (p.kn <= 0.0) ? 0.0 : 1.0 / p.kn;
			p.rt_a = (double)sv_cross(p.ra, m.t);
			p.rt_b = (double)sv_cross(p.rb, m.t);
			double kt = m.ma + m.mb + m.ia_ * p.rt_a * p.rt_a + m.ib_ * p.rt_b * p.rt_b;
			p.tangent_mass = (kt <= 0.0) ? 0.0 : 1.0 / kt;
			V2 vb = sv_vel_at(b, p.rb);
			V2 va = sv_vel_at(a, p.ra);
			double vn = (double)vdot(V2{ vb.x - va.x, vb.y - va.y }, m.n);
			double bias = 0.0;
			if (vn < -P.rest_thresh) bias = -e * vn;
			if (p.sep > 0.0) bias = std::max(bias, -p.sep / P.dt);
			p.vbias = bias;
			double pen = std::max(0.0, -p.sep - P.slop) * P.baumgarte / P.dt;
			p.pbias = std::min(pen, P.max_dep);
			p.pni = 0.0;
			p.ni = 0.0;
			p.ti = 0.0;
			if (we != nullptr) {
				for (int q = 0; q < we->count; ++q) {
					if (we->feat[q] == p.feature) { p.ni = we->ni[q]; p.ti = we->ti[q]; break; }
				}
			}
			sv_apply(a, b, m, i, sv_scale(m.n, p.ni));
			sv_apply(a, b, m, i, sv_scale(m.t, p.ti));
		}
		if (m.two) {
			m.k12 = m.ma + m.mb + m.ia_ * m.pts[0].rn_a * m.pts[1].rn_a
				+ m.ib_ * m.pts[0].rn_b * m.pts[1].rn_b;
		}
	}

	for (int32_t it = 0; it < P.iterations; ++it) {
		for (int32_t k = 0; k < nm; ++k) {
			SvMan &m = ms[k];
			sv_solve_manifold(m, bodies[m.ia], bodies[m.ib], P);
		}
		// 抓取约束与接触约束在**同一层迭代**（先流形后抓取，与 Solver.solve 同序），
		// 所以拖着物体撞墙时会自然互相制衡。
		for (int32_t i = 0; i < ng; ++i) {
			sv_solve_grab(bodies[grabs[i].ib], grabs[i], gacc[i * 2], gacc[i * 2 + 1]);
		}
	}

	for (int32_t k = 0; k < nm; ++k) {
		SvMan &m = ms[k];
		WarmEntry e;
		e.count = m.count;
		for (int i = 0; i < 2; ++i) {
			if (i < m.count) {
				e.feat[i] = m.pts[i].feature;
				// ⚠️ GDScript 的 store_warm 是 d[feature] = Vector2(ni, ti) ——
				// **Vector2 是 float32**，所以累积冲量在写进 warm 缓存时会被舍入一次。
				// 少了这一次舍入，两边的 warm start 从第 2 步起就会分叉
				// （第 1 步全是新接触、缓存为空，所以看不出差别）。
				e.ni[i] = (double)(float)m.pts[i].ni;
				e.ti[i] = (double)(float)m.pts[i].ti;
			} else { e.feat[i] = 0; e.ni[i] = 0.0; e.ti[i] = 0.0; }
		}
		warm[m.key] = e;
	}

	wr_i32b(out + 0, n);
	wr_i32b(out + 4, 0);
	for (int32_t i = 0; i < n; ++i) {
		uint8_t *o = out + 8 + i * SV_OUT;
		wr_f64(o + 0, (double)bodies[i].vel.x);
		wr_f64(o + 8, (double)bodies[i].vel.y);
		wr_f64(o + 16, bodies[i].w);
		wr_f64(o + 24, (double)bodies[i].pvel.x);
		wr_f64(o + 32, (double)bodies[i].pvel.y);
		wr_f64(o + 40, bodies[i].pw);
	}
}

} // namespace phys

// 整个 _broadphase 的 C++ 移植：扫掠 AABB -> OBB 表 -> 矩形 AABB -> SAP 配对 -> collide。
//
// 逐位等价的关键同样是"哪里是 float32、哪里是 float64"：
//   · Rect2 / Vector2 的一切都是 float32（含 grow / rotated / intersects 的中间量）
//   · Vector2::rotated 的**角度实参是 real_t**，所以 rotation 会先被截成 float
//     而 GDScript 的 cos(rotation) / sin(rotation) 用的是**完整 double** —— 两者不同，必须分别镜像
//   · GDScript 的裸 float（margin、radius、sep、ex/ey）是 float64
#pragma once
#include "collide_kernel.h"
#include <cstring>
#include <vector>
#include <algorithm>

namespace phys {

// ---------- Rect2（float32） ----------
struct R2 { float px, py, sx, sy; };

static inline R2 r2_grow(R2 r, float by) {
	// Rect2::grow_by：position -= by；size += by*2
	r.px -= by; r.py -= by;
	r.sx += by * 2.0f; r.sy += by * 2.0f;
	return r;
}

static inline bool r2_intersects(R2 a, R2 b) {
	// include_borders = true
	if (b.px > a.px + a.sx) return false;
	if (b.py > a.py + a.sy) return false;
	if (b.px + b.sx < a.px) return false;
	if (b.py + b.sy < a.py) return false;
	return true;
}

// ---------- Vector2 细节 ----------
// Vector2::rotated(real_t)：角度先截成 float，再算 sin/cos
static inline V2 v_rotated(V2 v, double angle) {
	float a = (float)angle;
	float s = (float)std::sin((double)a);
	float c = (float)std::cos((double)a);
	return V2{ v.x * c - v.y * s, v.x * s + v.y * c };
}

// ---------- 记录布局 ----------
static const int BODY_STRIDE = 104;   // 10*f64 + 6*i32
static const int RECT_STRIDE = 32;    //  4*f64
static const int BP_HEADER = 32;      // i32 n_bodies, i32 order_count, i32 out_cap, i32 pad, f64 dt, f64 max_margin
static const int MAN_STRIDE = 120;    // i32 ia,ib,ra,rb ; f64 nx,ny ; i32 count,pad ; 2*5*f64

static inline void wr_i32b(uint8_t *p, int32_t v) { std::memcpy(p, &v, 4); }
static inline int32_t rd_i32b(const uint8_t *p) { int32_t v; std::memcpy(&v, p, 4); return v; }

// 一个 body 的输入视图
struct BodyIn {
	V2 pos; double rot; V2 vel; double w;
	R2 aabb;
	int32_t is_static, awake, id, rect_off, rect_cnt;
};

static inline void load_body(const uint8_t *p, BodyIn &b) {
	b.pos = V2{ (float)rd_f64(p + 0), (float)rd_f64(p + 8) };
	b.rot = rd_f64(p + 16);
	b.vel = V2{ (float)rd_f64(p + 24), (float)rd_f64(p + 32) };
	b.w = rd_f64(p + 40);
	b.aabb.px = (float)rd_f64(p + 48);
	b.aabb.py = (float)rd_f64(p + 56);
	b.aabb.sx = (float)rd_f64(p + 64);
	b.aabb.sy = (float)rd_f64(p + 72);
	b.is_static = rd_i32b(p + 80);
	b.awake = rd_i32b(p + 84);
	b.id = rd_i32b(p + 88);
	b.rect_off = rd_i32b(p + 92);
	b.rect_cnt = rd_i32b(p + 96);
}

// 包围半径：0.5 * sqrt(e.x^2 + e.y^2)，e 是 aabb.size（float32 -> double）
static inline double body_radius(const BodyIn &b) {
	double ex = (double)b.aabb.sx;
	double ey = (double)b.aabb.sy;
	return 0.5 * std::sqrt(ex * ex + ey * ey);
}

// 本步扫掠范围：aabb.grow(motion)，motion 是 double，进 grow 时截成 float
static inline R2 swept_aabb(const BodyIn &b, double dt) {
	double motion = (double)vlen(b.vel) * dt + std::fabs(b.w) * body_radius(b) * dt;
	return r2_grow(b.aabb, (float)motion);
}

// OBB：镜像 Collide.obb_from_local_rect
static inline void build_obb(const BodyIn &b, const double *rect, OBB &o) {
	// hl = size * 0.5（Vector2 的 float32 运算）
	float hx = (float)rect[2] * 0.5f;
	float hy = (float)rect[3] * 0.5f;
	// local_center = rect.position + hl
	V2 lc = V2{ (float)rect[0] + hx, (float)rect[1] + hy };
	// center = position + lc.rotated(rotation)
	V2 rc = v_rotated(lc, b.rot);
	o.center = V2{ b.pos.x + rc.x, b.pos.y + rc.y };
	// u = Vector2(cos(rotation), sin(rotation)) —— 这里用的是完整 double 角度
	o.u = V2{ (float)std::cos(b.rot), (float)std::sin(b.rot) };
	o.v = V2{ -o.u.y, o.u.x };
	o.h = V2{ hx, hy };
}

// _obb_aabb：ex/ey 是 double，Rect2 存 float32
static inline R2 obb_aabb(const OBB &o) {
	double ex = std::fabs((double)o.u.x) * (double)o.h.x + std::fabs((double)o.v.x) * (double)o.h.y;
	double ey = std::fabs((double)o.u.y) * (double)o.h.x + std::fabs((double)o.v.y) * (double)o.h.y;
	R2 r;
	r.px = (float)((double)o.center.x - ex);
	r.py = (float)((double)o.center.y - ey);
	r.sx = (float)(ex * 2.0);
	r.sy = (float)(ey * 2.0);
	return r;
}

struct BpResult {
	int32_t manifolds_written;
};

// 主入口：把整个宽相跑完，流形写进 out（最多 cap 条）
static inline void run_broadphase(const uint8_t *body_bytes, const uint8_t *rect_bytes,
		const uint8_t *order_bytes, uint8_t *out, int32_t &out_count, int32_t &out_points) {
	int32_t n_bodies = rd_i32b(body_bytes + 0);
	int32_t order_count = rd_i32b(body_bytes + 4);
	int32_t cap = rd_i32b(body_bytes + 8);
	double dt = rd_f64(body_bytes + 16);
	double max_margin = rd_f64(body_bytes + 24);
	out_count = 0;
	out_points = 0;
	if (n_bodies <= 0 || order_count <= 0 || cap <= 0) return;

	std::vector<BodyIn> bodies(n_bodies);
	std::vector<R2> swept(n_bodies);
	std::vector<double> radius(n_bodies);
	for (int32_t i = 0; i < n_bodies; ++i) {
		load_body(body_bytes + BP_HEADER + i * BODY_STRIDE, bodies[i]);
		radius[i] = body_radius(bodies[i]);
		swept[i] = swept_aabb(bodies[i], dt);
	}
	// OBB + 矩形 AABB 表（按 rect 全局下标）
	int32_t total_rects = 0;
	for (int32_t i = 0; i < n_bodies; ++i) {
		if (bodies[i].rect_cnt > 0) total_rects = std::max(total_rects, bodies[i].rect_off + bodies[i].rect_cnt);
	}
	std::vector<OBB> obbs(total_rects);
	std::vector<R2> boxes(total_rects);
	for (int32_t i = 0; i < n_bodies; ++i) {
		const BodyIn &b = bodies[i];
		for (int32_t r = 0; r < b.rect_cnt; ++r) {
			int32_t idx = b.rect_off + r;
			build_obb(b, (const double *)(rect_bytes + (size_t)idx * RECT_STRIDE), obbs[idx]);
			boxes[idx] = obb_aabb(obbs[idx]);
		}
	}

	Sat sat;
	Result res;
	for (int32_t a = 0; a < order_count; ++a) {
		int32_t ia = rd_i32b(order_bytes + (size_t)a * 4);
		if (ia < 0 || ia >= n_bodies) continue;
		R2 sa = swept[ia];
		double max_x = (double)sa.px + (double)sa.sx;
		bool a_active = (bodies[ia].is_static == 0 && bodies[ia].awake != 0);
		double a_lo_y = (double)sa.py, a_hi_y = (double)sa.py + (double)sa.sy;
		for (int32_t b2 = a + 1; b2 < order_count; ++b2) {
			int32_t ib = rd_i32b(order_bytes + (size_t)b2 * 4);
			if (ib < 0 || ib >= n_bodies) continue;
			R2 sb = swept[ib];
			if ((double)sb.px > max_x) break;
			if (!a_active && !(bodies[ib].is_static == 0 && bodies[ib].awake != 0)) continue;
			double b_lo_y = (double)sb.py, b_hi_y = (double)sb.py + (double)sb.sy;
			if (a_hi_y <= b_lo_y || b_hi_y <= a_lo_y) continue;
			// ---- id 升序规范化（与 GDScript 一致）----
			int32_t na = ia, nb = ib;
			if (bodies[na].id > bodies[nb].id) { int32_t t = na; na = nb; nb = t; }
			const BodyIn &A = bodies[na];
			const BodyIn &B = bodies[nb];
			if (A.rect_cnt == 0 || B.rect_cnt == 0) continue;
			double rel = (double)vlen(V2{ B.vel.x - A.vel.x, B.vel.y - A.vel.y });
			double spin = std::fabs(A.w) * radius[na] + std::fabs(B.w) * radius[nb];
			double margin = std::min((rel + spin) * dt + 0.5, max_margin);
			for (int32_t ra = 0; ra < A.rect_cnt; ++ra) {
				int32_t ga = A.rect_off + ra;
				R2 box_a = r2_grow(boxes[ga], (float)margin);
				for (int32_t rb = 0; rb < B.rect_cnt; ++rb) {
					int32_t gb = B.rect_off + rb;
					R2 box_b = r2_grow(boxes[gb], (float)margin);
					if (!r2_intersects(box_a, box_b)) continue;
					if (out_count >= cap) return;
					collide(obbs[ga], obbs[gb], margin, sat, res);
					if (res.count <= 0) continue;
					uint8_t *o = out + (size_t)out_count * MAN_STRIDE;
					wr_i32b(o + 0, na);
					wr_i32b(o + 4, nb);
					wr_i32b(o + 8, ra);
					wr_i32b(o + 12, rb);
					wr_f64(o + 16, (double)res.normal.x);
					wr_f64(o + 24, (double)res.normal.y);
					wr_i32b(o + 32, res.count);
					wr_i32b(o + 36, 0);
					for (int k = 0; k < 2; ++k) {
						double v[5] = { 0, 0, 0, 0, 0 };
						if (k < res.count) {
							v[0] = res.pts[k].px; v[1] = res.pts[k].py;
							v[2] = res.pts[k].depth; v[3] = res.pts[k].sep; v[4] = res.pts[k].feature;
						}
						for (int j = 0; j < 5; ++j) wr_f64(o + 40 + (k * 5 + j) * 8, v[j]);
					}
					out_count++;
					out_points++;
				}
			}
		}
	}
}

} // namespace phys

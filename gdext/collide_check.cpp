// 逐位比对：读 GDScript 导出的 OBB 对 + 它的结果，跑 C++ 内核，逐个字段比。
#include "../gdext/collide_kernel.h"
#include <vector>
#include <chrono>
#include <cstring>
#include <algorithm>

using namespace phys;

struct Pair {
    OBB a, b;
    double margin;
    V2 gs_normal;
    int gs_count;
    Pt gs_pts[2];
};

int main(int argc, char **argv) {
    setvbuf(stdout, nullptr, _IONBF, 0);
    const char *path = (argc > 1) ? argv[1] : "collide_pairs.bin";
    FILE *f = fopen(path, "rb");
    if (!f) { printf("打不开 %s\n", path); return 1; }
    int32_t n = 0, npts = 0;
    if (fread(&n, 4, 1, f) != 1) { printf("读头部失败\n"); return 1; }
    if (fread(&npts, 4, 1, f) != 1) { printf("读头部失败\n"); return 1; }
    std::vector<Pair> pairs(n);
    for (int i = 0; i < n; ++i) {
        Pair &p = pairs[i];
        double v[8];
        for (int k = 0; k < 2; ++k) {
            if (fread(v, 8, 8, f) != 8) { printf("读第 %d 对失败\n", i); return 1; }
            OBB &o = (k == 0) ? p.a : p.b;
            o.center = v2((float)v[0], (float)v[1]);
            o.u = v2((float)v[2], (float)v[3]);
            o.v = v2((float)v[4], (float)v[5]);
            o.h = v2((float)v[6], (float)v[7]);
        }
        if (fread(&p.margin, 8, 1, f) != 1) return 1;
        double nrm[2];
        if (fread(nrm, 8, 2, f) != 2) return 1;
        p.gs_normal = v2((float)nrm[0], (float)nrm[1]);
        int32_t cnt = 0, pad = 0;
        if (fread(&cnt, 4, 1, f) != 1) return 1;
        if (fread(&pad, 4, 1, f) != 1) return 1;
        p.gs_count = cnt;
        for (int k = 0; k < 2; ++k) {
            double pt[5];
            if (fread(pt, 8, 5, f) != 5) return 1;
            p.gs_pts[k] = Pt{ pt[0], pt[1], pt[2], pt[3], pt[4] };
        }
    }
    fclose(f);

    // ---- 单对调试 ----
    if (argc > 2) {
        int idx = atoi(argv[2]);
        if (idx >= 0 && idx < n) {
            const Pair &p = pairs[idx];
            printf("=== 第 %d 对 (C++) ===\n", idx);
            Sat ds; Result dr;
            sat_signed_into(p.a, p.b, ds);
            printf("SAT sep=%.17f normal=(%.17f, %.17f) from_a=%d\n", ds.sep,
                   (double)ds.normal.x, (double)ds.normal.y, ds.from_a ? 1 : 0);
            if (ds.sep < 0.0) {
                bool from_a = ds.from_a;
                const OBB &ref = from_a ? p.a : p.b;
                const OBB &inc = from_a ? p.b : p.a;
                V2 ref_normal = from_a ? ds.normal : vneg(ds.normal);
                int ref_edge = 0; double best_dot = -INFINITY;
                for (int i = 0; i < 4; ++i) { double d = (double)vdot(obb_edge_normal(ref, i), ref_normal); if (d > best_dot) { best_dot = d; ref_edge = i; } }
                int inc_edge = 0; double worst_dot = INFINITY;
                for (int i = 0; i < 4; ++i) { double d2 = (double)vdot(obb_edge_normal(inc, i), ref_normal); if (d2 < worst_dot) { worst_dot = d2; inc_edge = i; } }
                V2 rp1 = obb_vertex(ref, ref_edge), rp2 = obb_vertex(ref, (ref_edge + 1) % 4);
                V2 ip1 = obb_vertex(inc, inc_edge), ip2 = obb_vertex(inc, (inc_edge + 1) % 4);
                printf("ref_edge=%d best_dot=%.17f inc_edge=%d worst_dot=%.17f\n", ref_edge, best_dot, inc_edge, worst_dot);
                printf("rp1=(%.17f, %.17f) rp2=(%.17f, %.17f)\n", (double)rp1.x,(double)rp1.y,(double)rp2.x,(double)rp2.y);
                printf("ip1=(%.17f, %.17f) ip2=(%.17f, %.17f)\n", (double)ip1.x,(double)ip1.y,(double)ip2.x,(double)ip2.y);
                V2 tangent = vnormalized(vsub(rp2, rp1));
                printf("tangent=(%.17f, %.17f) offset1=%.17f offset2=%.17f\n",
                       (double)tangent.x, (double)tangent.y, -(double)vdot(tangent, rp1), (double)vdot(tangent, rp2));
                V2 sg[2], sg2[2];
                int c1 = clip_segment(ip1, ip2, vneg(tangent), -(double)vdot(tangent, rp1), sg);
                printf("裁剪1 -> %d 点\n", c1);
                for (int i = 0; i < c1; ++i) printf("   seg[%d]=(%.17f, %.17f)\n", i, (double)sg[i].x, (double)sg[i].y);
                if (c1 > 0) {
                    int c2 = clip_segment(sg[0], sg[1], tangent, (double)vdot(tangent, rp2), sg2);
                    printf("裁剪2 -> %d 点\n", c2);
                    for (int i = 0; i < c2; ++i)
                        printf("   seg2[%d]=(%.17f, %.17f) separation=%.17f\n", i, (double)sg2[i].x, (double)sg2[i].y,
                               (double)vdot(vsub(sg2[i], rp1), ref_normal));
                }
            }
            collide(p.a, p.b, p.margin, ds, dr);
            printf("  collide -> 点数=%d\n", dr.count);
        }
        return 0;
    }

    // ---- 比对 ----
    Sat s;
    Result r;
    long long bad_normal = 0, bad_count = 0, bad_pt = 0, bad_all = 0;
    int shown = 0;
    for (int i = 0; i < n; ++i) {
        const Pair &p = pairs[i];
        collide(p.a, p.b, p.margin, s, r);
        bool bn = (std::memcmp(&r.normal, &p.gs_normal, sizeof(V2)) != 0);
        bool bc = (r.count != p.gs_count);
        bool bp = false;
        for (int k = 0; k < std::min(r.count, p.gs_count); ++k) {
            if (std::memcmp(&r.pts[k], &p.gs_pts[k], sizeof(Pt)) != 0) { bp = true; break; }
        }
        if (bn) bad_normal++;
        if (bc) bad_count++;
        if (bp) bad_pt++;
        if (bn || bc || bp) {
            bad_all++;
            if (shown < 6) {
                shown++;
                printf("差异 #%d: sep(norm) gs_count=%d c_count=%d | normal gs=(%.9g,%.9g) c=(%.9g,%.9g)\n",
                       i, p.gs_count, r.count, (double)p.gs_normal.x, (double)p.gs_normal.y,
                       (double)r.normal.x, (double)r.normal.y);
                for (int k = 0; k < std::max(r.count, p.gs_count) && k < 2; ++k)
                    printf("   p%d gs=(%.9g,%.9g,%.9g,%.9g,%.9g) c=(%.9g,%.9g,%.9g,%.9g,%.9g)\n", k,
                           p.gs_pts[k].px, p.gs_pts[k].py, p.gs_pts[k].depth, p.gs_pts[k].sep, p.gs_pts[k].feature,
                           r.pts[k].px, r.pts[k].py, r.pts[k].depth, r.pts[k].sep, r.pts[k].feature);
            }
        }
    }
    printf("\n=== 逐位比对：%d 对（GDScript 接触点 %d 个）===\n", n, npts);
    printf("  normal 不一致 : %lld\n", bad_normal);
    printf("  count  不一致 : %lld\n", bad_count);
    printf("  接触点 不一致 : %lld\n", bad_pt);
    printf("  任一不一致    : %lld  (%.4f%%)\n", bad_all, 100.0 * (double)bad_all / (double)n);

    // ---- 计时 ----
    double best = 1e18;
    long long sink = 0;
    for (int rep = 0; rep < 9; ++rep) {
        auto t0 = std::chrono::high_resolution_clock::now();
        for (int i = 0; i < n; ++i) {
            collide(pairs[i].a, pairs[i].b, pairs[i].margin, s, r);
            sink += r.count;
        }
        auto t1 = std::chrono::high_resolution_clock::now();
        best = std::min(best, std::chrono::duration<double, std::milli>(t1 - t0).count());
    }
    printf("  C++ 耗时: %.4f ms / %d 对 = %.0f ns/对 (sink=%lld)\n", best, n, best * 1e6 / n, sink);
    return 0;
}

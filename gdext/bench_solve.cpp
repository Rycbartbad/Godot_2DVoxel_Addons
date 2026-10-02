// GDExtension 探索第一步：不做管道，先回答"C++ 到底快多少"。
// 读 tests/dump_batch_bin.gd 导出的**同一份数据**，跑**同一套迭代循环**，
// 比时间也比结果 —— 这样"快多少倍"才是可比的。
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <vector>
#include <chrono>
#include <cmath>
#include <algorithm>

static std::vector<double> b_vx, b_vy, b_vw, b_px, b_py, b_pw, b_im, b_ii;
static std::vector<int32_t> b_wr;
static std::vector<double> m_nx, m_ny, m_tx, m_ty, m_mu, m_k12;
static std::vector<int32_t> m_p0, m_p1, m_two;
static std::vector<int32_t> p_ba, p_bb, p_feat;
static std::vector<double> p_rax, p_ray, p_rbx, p_rby, p_kn, p_nm, p_tm, p_vb, p_pb;
static std::vector<double> p_ni, p_ti, p_pni;

static int nb, nm, np, iterations;
static const bool USE_BLOCK = true;

static inline void apply_point(int pi, double ix, double iy) {
    if (ix == 0.0 && iy == 0.0) return;
    int ba = p_ba[pi], bb = p_bb[pi];
    if (b_wr[ba] == 1) {
        double ma = b_im[ba];
        b_vx[ba] -= ix * ma;
        b_vy[ba] -= iy * ma;
        b_vw[ba] -= b_ii[ba] * (p_rax[pi] * iy - p_ray[pi] * ix);
    }
    if (b_wr[bb] == 1) {
        double mb = b_im[bb];
        b_vx[bb] += ix * mb;
        b_vy[bb] += iy * mb;
        b_vw[bb] += b_ii[bb] * (p_rbx[pi] * iy - p_rby[pi] * ix);
    }
}

static inline void block(int mi, int q0, int q1) {
    double k11 = p_kn[q0], k22 = p_kn[q1], k12 = m_k12[mi];
    double nx = m_nx[mi], ny = m_ny[mi];
    int ba = p_ba[q0], bb = p_bb[q0];
    double vb1x = b_vx[bb] + (-b_vw[bb] * p_rby[q0]);
    double vb1y = b_vy[bb] + ( b_vw[bb] * p_rbx[q0]);
    double va1x = b_vx[ba] + (-b_vw[ba] * p_ray[q0]);
    double va1y = b_vy[ba] + ( b_vw[ba] * p_rax[q0]);
    int ba2 = p_ba[q1], bb2 = p_bb[q1];
    double vb2x = b_vx[bb2] + (-b_vw[bb2] * p_rby[q1]);
    double vb2y = b_vy[bb2] + ( b_vw[bb2] * p_rbx[q1]);
    double va2x = b_vx[ba2] + (-b_vw[ba2] * p_ray[q1]);
    double va2y = b_vy[ba2] + ( b_vw[ba2] * p_rax[q1]);
    double vn1 = (vb1x - va1x) * nx + (vb1y - va1y) * ny;
    double vn2 = (vb2x - va2x) * nx + (vb2y - va2y) * ny;
    double rhs1 = p_vb[q0] - vn1, rhs2 = p_vb[q1] - vn2;
    double x1 = p_ni[q0], x2 = p_ni[q1];
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
    p_ni[q0] = x1 + dx1;
    p_ni[q1] = x2 + dx2;
    apply_point(q0, nx * dx1, ny * dx1);
    apply_point(q1, nx * dx2, ny * dx2);
}

static void solve_range(int lo, int hi) {
    for (int it = 0; it < iterations; ++it) {
        for (int mi = lo; mi < hi; ++mi) {
            int q0 = m_p0[mi];
            bool two = USE_BLOCK && m_two[mi] == 1;
            if (two) block(mi, q0, m_p1[mi]);
            int cnt = (m_two[mi] == 1) ? 2 : 1;
            for (int k = 0; k < cnt; ++k) {
                int pi = (k == 0) ? q0 : m_p1[mi];
                int ba = p_ba[pi], bb = p_bb[pi];
                double nx = m_nx[mi], ny = m_ny[mi];
                bool wa = b_wr[ba] == 1, wb = b_wr[bb] == 1;
                double ma = b_im[ba], mb = b_im[bb], ia = b_ii[ba], ib = b_ii[bb];
                if (!two) {
                    double vbx = b_vx[bb] + (-b_vw[bb] * p_rby[pi]);
                    double vby = b_vy[bb] + ( b_vw[bb] * p_rbx[pi]);
                    double vax = b_vx[ba] + (-b_vw[ba] * p_ray[pi]);
                    double vay = b_vy[ba] + ( b_vw[ba] * p_rax[pi]);
                    double vn = (vbx - vax) * nx + (vby - vay) * ny;
                    double dl = p_nm[pi] * (p_vb[pi] - vn);
                    double newn = std::max(p_ni[pi] + dl, 0.0);
                    dl = newn - p_ni[pi];
                    p_ni[pi] = newn;
                    double ix = nx * dl, iy = ny * dl;
                    if (ix != 0.0 || iy != 0.0) {
                        if (wa) { b_vx[ba] -= ix * ma; b_vy[ba] -= iy * ma;
                                  b_vw[ba] -= ia * (p_rax[pi] * iy - p_ray[pi] * ix); }
                        if (wb) { b_vx[bb] += ix * mb; b_vy[bb] += iy * mb;
                                  b_vw[bb] += ib * (p_rbx[pi] * iy - p_rby[pi] * ix); }
                    }
                }
                if (p_pb[pi] > 0.0 && p_nm[pi] > 0.0) {
                    double pvbx = b_px[bb] + (-b_pw[bb] * p_rby[pi]);
                    double pvby = b_py[bb] + ( b_pw[bb] * p_rbx[pi]);
                    double pvax = b_px[ba] + (-b_pw[ba] * p_ray[pi]);
                    double pvay = b_py[ba] + ( b_pw[ba] * p_rax[pi]);
                    double pvn = (pvbx - pvax) * nx + (pvby - pvay) * ny;
                    double pdl = p_nm[pi] * (p_pb[pi] - pvn);
                    double pnew = std::max(p_pni[pi] + pdl, 0.0);
                    pdl = pnew - p_pni[pi];
                    p_pni[pi] = pnew;
                    double pix = nx * pdl, piy = ny * pdl;
                    if (pix != 0.0 || piy != 0.0) {
                        if (wa) { b_px[ba] -= pix * ma; b_py[ba] -= piy * ma;
                                  b_pw[ba] -= ia * (p_rax[pi] * piy - p_ray[pi] * pix); }
                        if (wb) { b_px[bb] += pix * mb; b_py[bb] += piy * mb;
                                  b_pw[bb] += ib * (p_rbx[pi] * piy - p_rby[pi] * pix); }
                    }
                }
                double tx = m_tx[mi], ty = m_ty[mi];
                double vbx3 = b_vx[bb] + (-b_vw[bb] * p_rby[pi]);
                double vby3 = b_vy[bb] + ( b_vw[bb] * p_rbx[pi]);
                double vax3 = b_vx[ba] + (-b_vw[ba] * p_ray[pi]);
                double vay3 = b_vy[ba] + ( b_vw[ba] * p_rax[pi]);
                double dt_imp = -p_tm[pi] * ((vbx3 - vax3) * tx + (vby3 - vay3) * ty);
                double max_f = m_mu[mi] * p_ni[pi];
                double newt = std::min(std::max(p_ti[pi] + dt_imp, -max_f), max_f);
                dt_imp = newt - p_ti[pi];
                p_ti[pi] = newt;
                double jx = tx * dt_imp, jy = ty * dt_imp;
                if (jx != 0.0 || jy != 0.0) {
                    if (wa) { b_vx[ba] -= jx * ma; b_vy[ba] -= jy * ma;
                              b_vw[ba] -= ia * (p_rax[pi] * jy - p_ray[pi] * jx); }
                    if (wb) { b_vx[bb] += jx * mb; b_vy[bb] += jy * mb;
                              b_vw[bb] += ib * (p_rbx[pi] * jy - p_rby[pi] * jx); }
                }
            }
        }
    }
}

template <typename T> static void read_vec(FILE* f, std::vector<T>& v, size_t n) {
    v.resize(n);
    if (n) fread(v.data(), sizeof(T), n, f);
}

int main(int argc, char** argv) {
    setvbuf(stdout, nullptr, _IONBF, 0);
    const char* path = (argc > 1) ? argv[1] : "batch.bin";
    FILE* f = fopen(path, "rb");
    if (!f) { printf("打不开 %s\n", path); return 1; }
    fread(&nb, 4, 1, f); fread(&nm, 4, 1, f); fread(&np, 4, 1, f); fread(&iterations, 4, 1, f);
    read_vec(f, b_vx, nb); read_vec(f, b_vy, nb); read_vec(f, b_vw, nb);
    read_vec(f, b_px, nb); read_vec(f, b_py, nb); read_vec(f, b_pw, nb);
    read_vec(f, b_im, nb); read_vec(f, b_ii, nb); read_vec(f, b_wr, (size_t)nb);
    read_vec(f, m_nx, nm); read_vec(f, m_ny, nm); read_vec(f, m_tx, nm);
    read_vec(f, m_ty, nm); read_vec(f, m_mu, nm); read_vec(f, m_k12, nm);
    read_vec(f, m_p0, (size_t)nm); read_vec(f, m_p1, (size_t)nm); read_vec(f, m_two, (size_t)nm);
    read_vec(f, p_ba, (size_t)np); read_vec(f, p_bb, (size_t)np); read_vec(f, p_feat, (size_t)np);
    read_vec(f, p_rax, np); read_vec(f, p_ray, np); read_vec(f, p_rbx, np); read_vec(f, p_rby, np);
    read_vec(f, p_kn, np); read_vec(f, p_nm, np); read_vec(f, p_tm, np);
    read_vec(f, p_vb, np); read_vec(f, p_pb, np);
    read_vec(f, p_ni, np); read_vec(f, p_ti, np); read_vec(f, p_pni, np);
    fclose(f);

    // 索引校验：错位的数据会在这里被挡住，而不是在求解循环里变成访问违例
    auto bad = [&](const char* what, const std::vector<int32_t>& v, int lo, int hi) {
        for (size_t i = 0; i < v.size(); ++i)
            if (v[i] < lo || v[i] > hi) {
                printf("索引越界: %s[%zu]=%d 允许 [%d,%d]\n", what, i, v[i], lo, hi);
                return true;
            }
        return false;
    };
    if (bad("b_wr", b_wr, 0, 1)) return 2;
    if (bad("p_ba", p_ba, 0, nb - 1)) return 2;
    if (bad("p_bb", p_bb, 0, nb - 1)) return 2;
    if (bad("m_p0", m_p0, 0, np - 1)) return 2;
    // 1 点流形的 m_p1 会写成 np（哨兵），循环里不会读它 —— 只校验 2 点流形
    for (int mi = 0; mi < nm; ++mi)
        if (m_two[mi] == 1 && (m_p1[mi] < 0 || m_p1[mi] > np - 1)) {
            printf("索引越界: m_p1[%d]=%d (两点流形)\n", mi, m_p1[mi]);
            return 2;
        }
    if (bad("m_two", m_two, 0, 1)) return 2;

    auto vx0 = b_vx, vy0 = b_vy, vw0 = b_vw, px0 = b_px, py0 = b_py, pw0 = b_pw;
    auto ni0 = p_ni, ti0 = p_ti, pni0 = p_pni;

    double best = 1e18;
    for (int rep = 0; rep < 7; ++rep) {
        b_vx = vx0; b_vy = vy0; b_vw = vw0; b_px = px0; b_py = py0; b_pw = pw0;
        p_ni = ni0; p_ti = ti0; p_pni = pni0;
        auto t0 = std::chrono::high_resolution_clock::now();
        solve_range(0, nm);
        auto t1 = std::chrono::high_resolution_clock::now();
        double ms = std::chrono::duration<double, std::milli>(t1 - t0).count();
        best = std::min(best, ms);
    }
    double sum = 0.0;
    for (int i = 0; i < nb; ++i) sum += b_vx[i] + b_vy[i] + b_vw[i] * 0.001;
    printf("场景: nb=%d nm=%d np=%d iterations=%d\n", nb, nm, np, iterations);
    printf("C++ 求解耗时: %.4f ms (min of 7)\n", best);
    printf("C++ 校验和:   %.12f\n", sum);
    return 0;
}

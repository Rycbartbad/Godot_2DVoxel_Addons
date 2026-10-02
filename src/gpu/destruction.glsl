#[compute]
#version 450

// 破坏内核：一个 invocation 处理一个 8x8 chunk。
//
// 设计取舍（这一版推翻了我最初的"每像素一个线程"写法）：
//   最初用 64 线程/ chunk + 共享内存做标签传播，结果被"读取-写入"时序问题坑了两次
//   （空像素渗标签、收敛判定提前退出），而且为了避开竞态把泛洪写成固定 64 轮之后
//   ￥速度直接掉到比 CPU 还慢。
//   现在改成：**GPU 在 chunk 之间并行，chunk 内部复用 CPU 那套 uint64 位运算泛洪**。
//   好处是彻底的：
//     - 没有共享内存、没有 barrier、没有 atomic -> 结构上不可能有竞态；
//     - 全整数位运算，结果与 CPU **逐位一致**（不是"近似一致"）；
//     - chunk 之间零依赖，576 个 chunk 直接铺满 SM。
//   GLSL 没有原生 uint64，所以用 uvec2 手写 64 位位运算。

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

layout(push_constant, std430) uniform Params {
	uint chunk_count;
	uint damage_count;
} params;

layout(set = 0, binding = 0, std430) restrict readonly buffer InOcc {
	uint occ[];          // 2 uint / chunk
} in_occ;

layout(set = 0, binding = 1, std430) restrict readonly buffer InAnchor {
	ivec2 anchor[];      // 1 ivec2 / chunk
} in_anchor;

layout(set = 0, binding = 2, std430) restrict readonly buffer InDamage {
	vec4 d[];            // 2 vec4 / damage: (type, radius, a.xy) (b.xy, half.xy)
} in_damage;

// 三个输出打包进同一个 buffer（一次回读），并且用 **SoA 平面布局**：
//   [0 .. 2n)            occ.lo/hi 交错
//   [2n .. 3n)           count
//   [3n .. 3n + 32n)     comp（每 chunk 32 个 uint）
// 平面布局的好处是 CPU 侧可以直接 slice() 出三段，而不是逐元素搬 18k 次
// （实测逐元素搬包比 GPU 计算本身还贵）。
layout(set = 0, binding = 3, std430) restrict buffer OutAll {
	uint data[];
} out_all;

const uint MAX_COMP = 16u;
const uint OVERFLOW_FLAG = 0x80000000u;

const uvec2 COL0 = uvec2(0x01010101u, 0x01010101u);
const uvec2 COL7 = uvec2(0x80808080u, 0x80808080u);
const uvec2 NOT_COL0 = uvec2(0xFEFEFEFEu, 0xFEFEFEFEu);
const uvec2 NOT_COL7 = uvec2(0x7F7F7F7Fu, 0x7F7F7F7Fu);

uvec2 m_and(uvec2 a, uvec2 b) { return uvec2(a.x & b.x, a.y & b.y); }
uvec2 m_or(uvec2 a, uvec2 b) { return uvec2(a.x | b.x, a.y | b.y); }
uvec2 m_andnot(uvec2 a, uvec2 b) { return uvec2(a.x & ~b.x, a.y & ~b.y); }
bool m_any(uvec2 a) { return (a.x | a.y) != 0u; }

uvec2 m_shl(uvec2 a, uint n) {
	if (n == 0u) { return a; }
	if (n >= 64u) { return uvec2(0u, 0u); }
	if (n >= 32u) { return uvec2(0u, a.x << (n - 32u)); }
	return uvec2(a.x << n, (a.y << n) | (a.x >> (32u - n)));
}

uvec2 m_shr(uvec2 a, uint n) {
	if (n == 0u) { return a; }
	if (n >= 64u) { return uvec2(0u, 0u); }
	if (n >= 32u) { return uvec2(a.y >> (n - 32u), 0u); }
	return uvec2((a.x >> n) | (a.y << (32u - n)), a.y >> n);
}

// 与 CPU 端 Bits.dilate4 完全同构的 4 邻域膨胀
uvec2 dilate4(uvec2 m) {
	uvec2 a = m_or(m, m_shl(m_and(m, NOT_COL7), 1u));
	uvec2 b = m_or(a, m_shr(m_and(m, NOT_COL0), 1u));
	uvec2 c = m_or(b, m_shl(m, 8u));
	return m_or(c, m_shr(m, 8u));
}

uvec2 flood(uvec2 seed, uvec2 occupancy) {
	uvec2 f = m_and(seed, occupancy);
	for (uint i = 0u; i < 64u; i++) {
		uvec2 n = m_and(dilate4(f), occupancy);
		if (n.x == f.x && n.y == f.y) { break; }
		f = n;
	}
	return f;
}

uint m_lowest_bit(uvec2 a) {
	if (a.x != 0u) { return uint(findLSB(a.x)); }
	return 32u + uint(findLSB(a.y));
}

bool bit_test(uvec2 a, uint p) {
	if (p < 32u) { return (a.x & (1u << p)) != 0u; }
	return (a.y & (1u << (p - 32u))) != 0u;
}

uvec2 bit_clear(uvec2 a, uint p) {
	if (p < 32u) { return uvec2(a.x & ~(1u << p), a.y); }
	return uvec2(a.x, a.y & ~(1u << (p - 32u)));
}

void main() {
	uint chunk = gl_GlobalInvocationID.x;
	if (chunk >= params.chunk_count) { return; }

	uvec2 occ = uvec2(in_occ.occ[chunk * 2u], in_occ.occ[chunk * 2u + 1u]);
	ivec2 anchor = in_anchor.anchor[chunk];

	// ---------- 1) 应用破坏 ----------
	for (uint p = 0u; p < 64u; p++) {
		if (!bit_test(occ, p)) { continue; }
		uint x = p & 7u;
		uint y = p >> 3u;
		vec2 wp = vec2(float(anchor.x) + float(x) + 0.5, float(anchor.y) + float(y) + 0.5);
		bool kill = false;
		for (uint i = 0u; i < params.damage_count; i++) {
			vec4 d0 = in_damage.d[i * 2u];
			vec4 d1 = in_damage.d[i * 2u + 1u];
			uint t = uint(d0.x);
			if (t == 0u) {
				vec2 dd = wp - d0.zw;
				if (dot(dd, dd) <= d0.y * d0.y) { kill = true; break; }
			} else if (t == 1u) {
				vec2 a = d0.zw;
				vec2 ab = d1.xy - a;
				float l2 = dot(ab, ab);
				float tt = (l2 > 1e-6) ? clamp(dot(wp - a, ab) / l2, 0.0, 1.0) : 0.0;
				vec2 ds = wp - (a + ab * tt);
				if (dot(ds, ds) <= d0.y * d0.y) { kill = true; break; }
			} else {
				vec2 dd2 = abs(wp - d0.zw);
				if (dd2.x <= d1.z && dd2.y <= d1.w) { kill = true; break; }
			}
		}
		if (kill) { occ = bit_clear(occ, p); }
	}

	// ---------- 2) 连通分量（与 CPU 逐位一致） ----------
	uint ncomp = 0u;
	uvec2 remaining = occ;
	while (m_any(remaining)) {
		uint lb = m_lowest_bit(remaining);
		uvec2 comp = flood(m_shl(uvec2(1u, 0u), lb), occ);
		if (ncomp < MAX_COMP) {
			uint comp_base = params.chunk_count * 3u + chunk * (MAX_COMP * 2u) + ncomp * 2u;
			out_all.data[comp_base] = comp.x;
			out_all.data[comp_base + 1u] = comp.y;
		}
		ncomp++;
		remaining = m_andnot(remaining, comp);
	}

	out_all.data[chunk * 2u] = occ.x;
	out_all.data[chunk * 2u + 1u] = occ.y;
	out_all.data[params.chunk_count * 2u + chunk] = (ncomp > MAX_COMP) ? (OVERFLOW_FLAG | ncomp) : ncomp;
}

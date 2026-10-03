// FastPhys —— 把热路径搬进 C++ 的 GDExtension。
//
// 当前实现：collide_batch（窄相批量）。
// 接口设计原则：**每帧一次批量调用**，而不是每对一次 —— 因为调用开销远大于单对成本。
//
// 关于数据传递（这里有个纯 C API 下的坑）：
//   往"传进来的" PackedByteArray 里写是**不安全**的 —— ptrcall 的实参指向调用现场的
//   Variant 副本，_copy_on_write 会把写入落到副本上，调用方看不到。
//   所以输出走**返回值**：先用拷贝构造函数按模板复制出一个等长数组，
//   再写它（此刻会 CoW，数据正好留在返回值里）。
#include "collide_kernel.h"
#include "bp_kernel.h"
#include "solver_kernel.h"
#include "gdextension_interface.h"
#include <cstdio>
#include <cstring>
#include <cstdint>
#include <string>
#include <vector>
// windows.h 只用来做运行时动态加载；宏要收窄，否则 min/max 会污染其它头
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

using namespace phys;

// ---- 输入 / 输出 步长（必须与 GDScript 侧严格一致）----
static const int IN_STRIDE = 8 * 8 * 2 + 8;   // a(8) + b(8) + margin(1) 个 double = 136
static const int OUT_STRIDE = 16 + 8 + 5 * 8 * 2; // normal(2f64) + count+pad + 2点*5f64 = 104

static GDExtensionInterfaceGetProcAddress g_get_proc_address = nullptr;
static GDExtensionClassLibraryPtr g_library = nullptr;

static GDExtensionInterfaceClassdbRegisterExtensionClass6 g_register_class6 = nullptr;
static GDExtensionInterfaceClassdbRegisterExtensionClassMethod g_register_method = nullptr;
static GDExtensionInterfaceClassdbConstructObject g_construct_object = nullptr;
static GDExtensionInterfaceObjectSetInstance g_object_set_instance = nullptr;
static GDExtensionInterfaceStringNameNewWithUtf8Chars g_sn_new = nullptr;
static GDExtensionInterfaceStringNewWithUtf8Chars g_str_new = nullptr;
static GDExtensionInterfaceVariantGetPtrConstructor g_get_ctor = nullptr;
static GDExtensionInterfacePackedByteArrayOperatorIndex g_pba_index = nullptr;
static GDExtensionInterfacePackedByteArrayOperatorIndexConst g_pba_index_const = nullptr;
static GDExtensionPtrConstructor g_pba_copy_ctor = nullptr;
static GDExtensionPtrConstructor g_pba_default_ctor = nullptr;
static GDExtensionInterfaceVariantGetPtrBuiltinMethod g_get_builtin = nullptr;
static GDExtensionPtrBuiltInMethod g_pba_resize = nullptr;

// ---- Variant <-> 内置类型 的官方转换接口 ----
// 这是纯 C API 里最关键的一组：没有它就得自己去猜 Variant 的内存布局。
//   to_type  : 把 Variant 拆成内置类型值（读实参）
//   from_type: 把内置类型值装进 Variant（写返回值）
// 两者都是**拷贝语义**，所以源/目标用完都要各自析构。
static GDExtensionInterfaceGetVariantToTypeConstructor g_get_to_type = nullptr;
static GDExtensionInterfaceGetVariantFromTypeConstructor g_get_from_type = nullptr;
static GDExtensionInterfaceVariantGetPtrDestructor g_get_destructor = nullptr;
static GDExtensionTypeFromVariantConstructorFunc g_pba_from_variant = nullptr;
static GDExtensionVariantFromTypeConstructorFunc g_pba_to_variant = nullptr;
static GDExtensionPtrDestructor g_pba_destructor = nullptr;
static GDExtensionTypeFromVariantConstructorFunc g_int_from_variant = nullptr;
static GDExtensionPtrDestructor g_int_destructor = nullptr;

// 内置类型值的暂存空间（PackedByteArray 实际只有 8 字节，给足余量）
struct TypeStorage { alignas(16) unsigned char buf[64]; };

struct SN { alignas(16) unsigned char buf[64]; };
static SN g_sn_class, g_sn_parent, g_sn_method;
static SN g_sn_ret, g_sn_a0, g_sn_a1, g_sn_a2, g_sn_a3;
static SN g_sn_bp;          // 方法名 broadphase
static SN g_sn_sv, g_sn_sv0, g_sn_sv1, g_sn_sv2, g_sn_svret, g_sn_cw;
static SN g_sn_bp0, g_sn_bp1, g_sn_bp2, g_sn_bp3;
static SN g_sn_bpret;
static SN g_sn_resize;      // PackedByteArray.resize 的 StringName
// PackedByteArray.resize 的 hash —— 从 extension_api.json 里取，不能瞎猜
static const int64_t PBA_RESIZE_HASH = 848867239;
// ⚠️ PropertyInfo 里的 class_name / hint_string **不能给 nullptr** ——
// Godot 会根据它们构造 PropertyInfo，空指针会直接段错误。
// 之前那次 signal 11 就是这里：注册方法时没有任何输出就崩了。
static SN g_sn_empty_class;
alignas(16) static unsigned char g_str_empty_hint[64];

// 批量窄相：一趟跑完 n 对
static GDExtensionPtrConstructor g_dummy_unused = nullptr;

static inline void load_obb(const uint8_t *p, OBB &o) {
	o.center = v2((float)rd_f64(p + 0), (float)rd_f64(p + 8));
	o.u = v2((float)rd_f64(p + 16), (float)rd_f64(p + 24));
	o.v = v2((float)rd_f64(p + 32), (float)rd_f64(p + 40));
	o.h = v2((float)rd_f64(p + 48), (float)rd_f64(p + 56));
}

// 新接口：OBB 表只传一次，每对只传两个字节偏移 + 一个 margin。
// 旧接口每对要搬 16 个 double，实测那一步把 60x 的内核收益吃成了 1.45x。
static void run_collide_batch(const uint8_t *obb, const uint8_t *pairs, uint8_t *out, int64_t n) {
	Sat s;
	Result r;
	for (int64_t i = 0; i < n; ++i) {
		const uint8_t *pr = pairs + i * 16;
		int32_t bo_a = 0, bo_b = 0;
		std::memcpy(&bo_a, pr, 4);
		std::memcpy(&bo_b, pr + 4, 4);
		double margin = rd_f64(pr + 8);
		OBB a, b;
		load_obb(obb + bo_a, a);
		load_obb(obb + bo_b, b);
		collide(a, b, margin, s, r);
		uint8_t *op = out + i * OUT_STRIDE;
		wr_f64(op + 0, (double)r.normal.x);
		wr_f64(op + 8, (double)r.normal.y);
		wr_i32(op + 16, r.count);
		wr_i32(op + 20, 0);
		for (int k = 0; k < 2; ++k) {
			double v[5] = { 0.0, 0.0, 0.0, 0.0, 0.0 };
			if (k < r.count) {
				v[0] = r.pts[k].px; v[1] = r.pts[k].py; v[2] = r.pts[k].depth;
				v[3] = r.pts[k].sep; v[4] = r.pts[k].feature;
			}
			for (int j = 0; j < 5; ++j) wr_f64(op + 24 + (k * 5 + j) * 8, v[j]);
		}
	}
}

// 注：曾经实现过一个 ptrcall 版本，但实测 **GDScript 一律走 call_func（Variant）**，
// 那条路根本不会被执行，留着只会腐坏。已删除，ptrcall_func 置空。

static void call_collide_batch(void *method_userdata, GDExtensionClassInstancePtr p_instance,
		const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count,
		GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
	// **GDScript 实际走的是这条路，不是 ptrcall**（实测：注册了 ptrcall，GDScript
	// 依然走 Variant 调用）。所以编组必须在 call_func 里做。
	if (r_error) r_error->error = GDEXTENSION_CALL_OK;
	if (p_argument_count < 3) {
		if (r_error) r_error->error = GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS;
		return;
	}
	if (p_argument_count < 4) {
		if (r_error) r_error->error = GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS;
		return;
	}
	TypeStorage cnt, obb_s, pairs_s, out_s;
	g_int_from_variant(cnt.buf, (GDExtensionVariantPtr)p_args[3]);
	int64_t n = *(int64_t *)cnt.buf;
	if (g_int_destructor) g_int_destructor(cnt.buf);   // POD 类型没有析构函数

	g_pba_from_variant(obb_s.buf, (GDExtensionVariantPtr)p_args[0]);
	g_pba_from_variant(pairs_s.buf, (GDExtensionVariantPtr)p_args[1]);
	g_pba_from_variant(out_s.buf, (GDExtensionVariantPtr)p_args[2]);   // 按模板拷贝，长度正确

	if (n > 0) {
		const uint8_t *obb = g_pba_index_const(obb_s.buf, 0);
		const uint8_t *pairs = g_pba_index_const(pairs_s.buf, 0);
		uint8_t *out = g_pba_index(out_s.buf, 0);
		if (obb && pairs && out) run_collide_batch(obb, pairs, out, n);
	}
	g_pba_to_variant(r_return, out_s.buf);

	g_pba_destructor(obb_s.buf);
	g_pba_destructor(pairs_s.buf);
	g_pba_destructor(out_s.buf);
}

// warm start 缓存挂在**实例**上，而不是全局。
// 这一点很关键：一个进程里可能同时存在多个 PWorld（测试就是这么干的），
// 用全局缓存会让它们互相污染累积冲量。
struct InstanceData {
	int marker;
	std::unordered_map<int64_t, phys::WarmEntry> warm;
};

static GDExtensionObjectPtr create_instance(void *p_userdata, GDExtensionBool p_notify_postinitialize) {
	GDExtensionObjectPtr obj = g_construct_object((GDExtensionConstStringNamePtr)g_sn_parent.buf);
	if (obj == nullptr) return nullptr;
	InstanceData *d = new InstanceData();
	d->marker = 0x5A5A;
	g_object_set_instance(obj, (GDExtensionConstStringNamePtr)g_sn_class.buf, (GDExtensionClassInstancePtr)d);
	return obj;
}

static void free_instance(void *p_userdata, GDExtensionClassInstancePtr p_instance) {
	if (p_instance != nullptr) delete (InstanceData *)p_instance;
}

static void register_collide_batch() {
	GDExtensionClassMethodInfo mi = {};
	mi.name = (GDExtensionStringNamePtr)g_sn_method.buf;
	mi.method_userdata = nullptr;
	mi.call_func = call_collide_batch;
	mi.ptrcall_func = nullptr;
	mi.method_flags = GDEXTENSION_METHOD_FLAG_NORMAL;
	mi.has_return_value = true;
	static GDExtensionPropertyInfo ret_info = {};
	ret_info.type = GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY;
	ret_info.name = (GDExtensionStringNamePtr)g_sn_ret.buf;
	ret_info.class_name = (GDExtensionStringNamePtr)g_sn_empty_class.buf;
	ret_info.hint_string = (GDExtensionStringPtr)g_str_empty_hint;
	mi.return_value_info = &ret_info;
	mi.return_value_metadata = GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE;

	static GDExtensionPropertyInfo arg_info[4] = {};
	arg_info[0].type = GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY;
	arg_info[0].name = (GDExtensionStringNamePtr)g_sn_a0.buf;
	arg_info[1].type = GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY;
	arg_info[1].name = (GDExtensionStringNamePtr)g_sn_a1.buf;
	arg_info[2].type = GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY;
	arg_info[2].name = (GDExtensionStringNamePtr)g_sn_a2.buf;
	arg_info[3].type = GDEXTENSION_VARIANT_TYPE_INT;
	arg_info[3].name = (GDExtensionStringNamePtr)g_sn_a3.buf;
	for (int i = 0; i < 4; ++i) {
		arg_info[i].class_name = (GDExtensionStringNamePtr)g_sn_empty_class.buf;
		arg_info[i].hint_string = (GDExtensionStringPtr)g_str_empty_hint;
	}
	static GDExtensionClassMethodArgumentMetadata meta[4] = {
		GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE,
		GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE,
		GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE,
		GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT64,
	};
	mi.argument_count = 4;
	mi.arguments_info = arg_info;
	mi.arguments_metadata = meta;
	mi.default_argument_count = 0;
	mi.default_arguments = nullptr;
	g_register_method(g_library, (GDExtensionConstStringNamePtr)g_sn_class.buf, &mi);
	printf("[FastPhys] 已注册方法 collide_batch（ptrcall）\n");
}

// ================= broadphase =================
// 整个 _broadphase 一趟跑完，流形按定长记录返回。
// 输出长度由 C++ 自己算（GDScript 事先不知道有多少条），所以这里必须
// 现造一个 PackedByteArray：默认构造 -> resize -> 填字节 -> 装进返回值。
static std::vector<uint8_t> g_bp_scratch;
static const int32_t BP_CAP0 = 1024;

static void call_broadphase(void *method_userdata, GDExtensionClassInstancePtr p_instance,
		const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count,
		GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
	if (r_error) r_error->error = GDEXTENSION_CALL_OK;
	if (p_argument_count < 4) {
		if (r_error) r_error->error = GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS;
		return;
	}
	TypeStorage body_s, rect_s, ord_s;
	g_pba_from_variant(body_s.buf, (GDExtensionVariantPtr)p_args[0]);
	g_pba_from_variant(rect_s.buf, (GDExtensionVariantPtr)p_args[1]);
	g_pba_from_variant(ord_s.buf, (GDExtensionVariantPtr)p_args[2]);
	const uint8_t *body = g_pba_index_const(body_s.buf, 0);
	const uint8_t *rect = g_pba_index_const(rect_s.buf, 0);
	const uint8_t *ord = g_pba_index_const(ord_s.buf, 0);
	int32_t written = 0;
	int32_t points = 0;
	// 输出走"按模板拷贝"（与 collide_batch 同一条已验证过的路）。
	// ⚠️ 不要试图在 C++ 里 resize 一个 PackedByteArray —— 那条路在这里实测直接段错误。
	// 代价是模板必须由调用方给足；被截断时返回条数 == 容量，调用方据此扩容重试。
	int32_t cap = 0;
	// ⚠️ 拷贝构造函数的实参必须是**真正的 PackedByteArray 类型值指针**，
	// 不能把 Variant 指针直接塞进去 —— 那样是未定义行为（实测会把堆写坏，
	// 随后在毫不相干的地方报 "mem is null" / "_copy_on_write() is true"）。
	// ⚠️ 拷贝构造是"类型值 -> 类型值"，不能直接写进 r_return（那是 Variant，
	// 类型标签不会被设置，Godot 会当成 Nil）。最后必须用 to_variant 装回去。
	TypeStorage shape_s, out_s;
	g_pba_from_variant(shape_s.buf, (GDExtensionVariantPtr)p_args[3]);
	GDExtensionConstTypePtr ctor_args[1] = { shape_s.buf };
	g_pba_copy_ctor(out_s.buf, ctor_args);
	if (body != nullptr && rect != nullptr && ord != nullptr) {
		int32_t shape_bytes = 0;
		{
			// PackedByteArray 的大小只能通过下标访问拿到；用 resize 的思路行不通，这里直接读头。
			// 头部 8 字节由 GDScript 写成 [cap][0]，所以容量可以从头里读。
			cap = 0;
			std::memcpy(&cap, body + 8, 4);   // 复用 body 头里的 out_cap
		}
		if (cap > 0) {
			int32_t guard_cap = cap;
			for (int guard = 0; guard < 12; ++guard) {
				g_bp_scratch.resize((size_t)guard_cap * phys::MAN_STRIDE);
				written = 0;
				points = 0;
				phys::run_broadphase(body, rect, ord, g_bp_scratch.data(), written, points);
				if (written < guard_cap) break;
				guard_cap *= 2;
				// 缓存放不下更多了：把实际容量告诉调用方，让它换大模板重来
				if (guard_cap > cap) { written = cap; break; }
			}
		}
	}
	uint8_t *dst = g_pba_index(out_s.buf, 0);
	if (dst != nullptr) {
		int32_t cnt = written;
		std::memcpy(dst, &cnt, 4);
		std::memcpy(dst + 4, &points, 4);   // 接触点总数，GDScript 拿它当 last_contacts
		if (written > 0) std::memcpy(dst + 8, g_bp_scratch.data(), (size_t)written * phys::MAN_STRIDE);
	}
	g_pba_to_variant(r_return, out_s.buf);
	g_pba_destructor(out_s.buf);
	g_pba_destructor(shape_s.buf);
	g_pba_destructor(body_s.buf);
	g_pba_destructor(rect_s.buf);
	g_pba_destructor(ord_s.buf);
}

static void register_broadphase() {
	GDExtensionClassMethodInfo mi = {};
	mi.name = (GDExtensionStringNamePtr)g_sn_bp.buf;
	mi.call_func = call_broadphase;
	mi.ptrcall_func = nullptr;
	mi.method_flags = GDEXTENSION_METHOD_FLAG_NORMAL;
	static GDExtensionPropertyInfo ret_info = {};
	ret_info.type = GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY;
	ret_info.name = (GDExtensionStringNamePtr)g_sn_bpret.buf;
	ret_info.class_name = (GDExtensionStringNamePtr)g_sn_empty_class.buf;
	ret_info.hint_string = (GDExtensionStringPtr)g_str_empty_hint;
	mi.has_return_value = true;
	mi.return_value_info = &ret_info;
	mi.return_value_metadata = GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE;
	static GDExtensionPropertyInfo ai[4] = {};
	GDExtensionStringNamePtr names[4] = {
		(GDExtensionStringNamePtr)g_sn_bp0.buf,
		(GDExtensionStringNamePtr)g_sn_bp1.buf,
		(GDExtensionStringNamePtr)g_sn_bp2.buf,
		(GDExtensionStringNamePtr)g_sn_bp3.buf,
	};
	for (int i = 0; i < 4; ++i) {
		ai[i].type = GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY;
		ai[i].name = names[i];
		ai[i].class_name = (GDExtensionStringNamePtr)g_sn_empty_class.buf;
		ai[i].hint_string = (GDExtensionStringPtr)g_str_empty_hint;
	}
	static GDExtensionClassMethodArgumentMetadata bmeta[4] = {
		GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE,
		GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE,
		GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE,
		GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE,
	};
	mi.argument_count = 4;
	mi.arguments_info = ai;
	mi.arguments_metadata = bmeta;
	g_register_method(g_library, (GDExtensionConstStringNamePtr)g_sn_class.buf, &mi);
	printf("[FastPhys] 已注册方法 broadphase\n");
}


// ================= solve =================
// 求解器直接吃宽相的打包输出 —— 于是**连流形对象都不用建**（那正是剩下的大头）。
static void call_solve(void *method_userdata, GDExtensionClassInstancePtr p_instance,
		const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count,
		GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
	if (r_error) r_error->error = GDEXTENSION_CALL_OK;
	if (p_argument_count < 3) {
		if (r_error) r_error->error = GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS;
		return;
	}
	TypeStorage bod_s, man_s, shape_s, out_s;
	g_pba_from_variant(bod_s.buf, (GDExtensionVariantPtr)p_args[0]);
	g_pba_from_variant(man_s.buf, (GDExtensionVariantPtr)p_args[1]);
	g_pba_from_variant(shape_s.buf, (GDExtensionVariantPtr)p_args[2]);
	GDExtensionConstTypePtr ctor_args[1] = { shape_s.buf };
	g_pba_copy_ctor(out_s.buf, ctor_args);
	const uint8_t *bod = g_pba_index_const(bod_s.buf, 0);
	const uint8_t *mans = g_pba_index_const(man_s.buf, 0);
	uint8_t *out = g_pba_index(out_s.buf, 0);
	InstanceData *inst = (InstanceData *)p_instance;
	if (bod != nullptr && mans != nullptr && out != nullptr && inst != nullptr) {
		phys::sv_run(bod, mans, out, inst->warm);
	}
	g_pba_to_variant(r_return, out_s.buf);
	g_pba_destructor(out_s.buf);
	g_pba_destructor(shape_s.buf);
	g_pba_destructor(bod_s.buf);
	g_pba_destructor(man_s.buf);
}

static void call_clear_warm(void *method_userdata, GDExtensionClassInstancePtr p_instance,
		const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count,
		GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
	if (r_error) r_error->error = GDEXTENSION_CALL_OK;
	InstanceData *inst = (InstanceData *)p_instance;
	if (inst != nullptr) inst->warm.clear();
}

// 诊断探针：把 warm 缓存里 (key, ni, ti) 全部吐出来，用于和 GDScript 的 _warm 逐项比对
static GDExtensionVariantFromTypeConstructorFunc g_int_to_variant = nullptr;
static GDExtensionPtrDestructor g_int_dtor2 = nullptr;

static void call_warm_probe(void *md, GDExtensionClassInstancePtr p_instance,
		const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count,
		GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
	if (r_error) r_error->error = GDEXTENSION_CALL_OK;
	InstanceData *inst = (InstanceData *)p_instance;
	TypeStorage arr;
	g_pba_default_ctor(arr.buf, nullptr);
	int32_t cnt = inst ? (int32_t)inst->warm.size() : 0;
	// 用返回的 Variant 承载一个 PackedByteArray：先建空数组不行（不能 resize），
	// 所以这里改走"模板拷贝"的老路 —— 调用方给模板。
	TypeStorage shape_s, out_s;
	g_pba_from_variant(shape_s.buf, (GDExtensionVariantPtr)p_args[0]);
	GDExtensionConstTypePtr ca[1] = { shape_s.buf };
	g_pba_copy_ctor(out_s.buf, ca);
	uint8_t *dst = g_pba_index(out_s.buf, 0);
	if (dst != nullptr && inst != nullptr) {
		int32_t k = 0;
		for (auto &kv : inst->warm) {
			for (int q = 0; q < kv.second.count; ++q) {
				if (k >= 64) break;
				uint8_t *o = dst + 8 + k * 48;
				int64_t key = kv.first;
				std::memcpy(o, &key, 8);
				int32_t feat = kv.second.feat[q];
				std::memcpy(o + 8, &feat, 4);
				wr_f64(o + 16, kv.second.ni[q]);
				wr_f64(o + 24, kv.second.ti[q]);
				k++;
			}
		}
		std::memcpy(dst, &k, 4);   // 实际吐出的记录数（每条键最多 2 条）
	}
	g_pba_to_variant(r_return, out_s.buf);
	g_pba_destructor(out_s.buf);
	g_pba_destructor(shape_s.buf);
	g_pba_destructor(arr.buf);
}

static SN g_sn_probe;
static SN g_sn_probe0;

static void register_solve() {
	// ---- solve(bod, mans, shape) -> PackedByteArray ----
	{
		GDExtensionClassMethodInfo mi = {};
		mi.name = (GDExtensionStringNamePtr)g_sn_sv.buf;
		mi.call_func = call_solve;
		mi.method_flags = GDEXTENSION_METHOD_FLAG_NORMAL;
		static GDExtensionPropertyInfo ri = {};
		ri.type = GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY;
		ri.name = (GDExtensionStringNamePtr)g_sn_svret.buf;
		ri.class_name = (GDExtensionStringNamePtr)g_sn_empty_class.buf;
		ri.hint_string = (GDExtensionStringPtr)g_str_empty_hint;
		mi.has_return_value = true;
		mi.return_value_info = &ri;
		mi.return_value_metadata = GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE;
		static GDExtensionPropertyInfo ai[3] = {};
		GDExtensionStringNamePtr names[3] = {
			(GDExtensionStringNamePtr)g_sn_sv0.buf,
			(GDExtensionStringNamePtr)g_sn_sv1.buf,
			(GDExtensionStringNamePtr)g_sn_sv2.buf,
		};
		for (int i = 0; i < 3; ++i) {
			ai[i].type = GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY;
			ai[i].name = names[i];
			ai[i].class_name = (GDExtensionStringNamePtr)g_sn_empty_class.buf;
			ai[i].hint_string = (GDExtensionStringPtr)g_str_empty_hint;
		}
		static GDExtensionClassMethodArgumentMetadata meta[3] = {
			GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE,
			GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE,
			GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE,
		};
		mi.argument_count = 3;
		mi.arguments_info = ai;
		mi.arguments_metadata = meta;
		g_register_method(g_library, (GDExtensionConstStringNamePtr)g_sn_class.buf, &mi);
		printf("[FastPhys] 已注册方法 solve\n");
	}
	// ---- warm_probe(shape) : 诊断用 ----
	{
		GDExtensionClassMethodInfo mi = {};
		mi.name = (GDExtensionStringNamePtr)g_sn_probe.buf;
		mi.call_func = call_warm_probe;
		mi.method_flags = GDEXTENSION_METHOD_FLAG_NORMAL;
		static GDExtensionPropertyInfo ri = {};
		ri.type = GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY;
		ri.name = (GDExtensionStringNamePtr)g_sn_bpret.buf;
		ri.class_name = (GDExtensionStringNamePtr)g_sn_empty_class.buf;
		ri.hint_string = (GDExtensionStringPtr)g_str_empty_hint;
		mi.has_return_value = true;
		mi.return_value_info = &ri;
		static GDExtensionPropertyInfo ai1[1] = {};
		ai1[0].type = GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY;
		ai1[0].name = (GDExtensionStringNamePtr)g_sn_probe0.buf;
		ai1[0].class_name = (GDExtensionStringNamePtr)g_sn_empty_class.buf;
		ai1[0].hint_string = (GDExtensionStringPtr)g_str_empty_hint;
		static GDExtensionClassMethodArgumentMetadata m1[1] = { GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE };
		mi.argument_count = 1;
		mi.arguments_info = ai1;
		mi.arguments_metadata = m1;
		g_register_method(g_library, (GDExtensionConstStringNamePtr)g_sn_class.buf, &mi);
	}
	// ---- clear_warm() ----
	{
		GDExtensionClassMethodInfo mi = {};
		mi.name = (GDExtensionStringNamePtr)g_sn_cw.buf;
		mi.call_func = call_clear_warm;
		mi.method_flags = GDEXTENSION_METHOD_FLAG_NORMAL;
		mi.has_return_value = false;
		mi.argument_count = 0;
		g_register_method(g_library, (GDExtensionConstStringNamePtr)g_sn_class.buf, &mi);
		printf("[FastPhys] 已注册方法 clear_warm\n");
	}
}


// ================= RapierPhys：把物理交给 Rapier =================
//
// 只做**薄包装**，两个理由：
//   · 桥接层 rapier_bridge.dll 是 MSVC Rust 编的，本 DLL 是 MinGW g++ 编的 ——
//     链接期混用导入库容易出问题，所以用 LoadLibrary **运行时**取函数指针。
//   · GDScript 侧只有**一个**方法 cmd(in, out)：in 是命令流，out 是结果流。
//     手写 GDExtension 的注册样板很重，注册面越小越好；而且这层胶水迟早会被
//     真正的 PWorld 集成取代（那时命令流会变成批量位姿/矩形同步）。
//
// 命令流（小端；全部 memcpy 读写，不要求对齐）：
//   in  = [i32 out_cap][命令...]
//   out = [i32 written][结果...]        written 是结果段的字节数
//
//   0  reset()                                    -> i32 ok(0 成功)
//   1  set_gravity(f64 x, f64 y)
//   2  step(f64 dt)
//   3  body_new(i32 is_static, f64 x, y, rot)     -> i32 id
//   4  body_remove(u32 id)
//   5  body_set_rects(u32 id, i32 count, f32[count*4], f64 friction)
//   6  body_set_pose(u32 id, f64 x, y, rot)
//   7  body_set_vel(u32 id, f64 vx, vy, w)
//   8  body_get_state(u32 id)                     -> f64 x, y, rot, vx, vy, w
//   9  body_is_sleeping(u32 id)                   -> i32
//  10  body_wake(u32 id)
//  11  contact_count()                            -> i32
//  12  contact_get(i32 idx)                       -> f64 id_a, id_b, nx, ny, px, py, dist
//  13  body_count()                               -> i32
//  14  body_add_force(u32 id, f64 fx, fy, torque)
//  15  body_set_type(u32 id, i32 is_static)

typedef void *RPWorld;

struct RapierApi {
	HMODULE dll = nullptr;
	RPWorld (*world_new)() = nullptr;
	void (*world_free)(RPWorld) = nullptr;
	void (*world_set_gravity)(RPWorld, double, double) = nullptr;
	void (*world_step)(RPWorld, double) = nullptr;
	uint32_t (*body_new)(RPWorld, int32_t, double, double, double) = nullptr;
	void (*body_remove)(RPWorld, uint32_t) = nullptr;
	void (*body_set_rects)(RPWorld, uint32_t, const float *, int32_t, double) = nullptr;
	void (*body_set_pose)(RPWorld, uint32_t, double, double, double) = nullptr;
	void (*body_set_vel)(RPWorld, uint32_t, double, double, double) = nullptr;
	int32_t (*body_get_state)(RPWorld, uint32_t, double *) = nullptr;
	int32_t (*body_is_sleeping)(RPWorld, uint32_t) = nullptr;
	void (*body_wake)(RPWorld, uint32_t) = nullptr;
	int32_t (*contact_count)(RPWorld) = nullptr;
	int32_t (*contact_get)(RPWorld, int32_t, double *) = nullptr;
	int32_t (*body_count)(RPWorld) = nullptr;
	void (*body_add_force)(RPWorld, uint32_t, double, double, double) = nullptr;
	void (*body_set_type)(RPWorld, uint32_t, int32_t) = nullptr;
	bool tried = false;
	bool ok = false;
};

static RapierApi g_rap;
static SN g_sn_rp_class, g_sn_rp_cmd, g_sn_rp_a0, g_sn_rp_a1, g_sn_rp_ret;

// 只用来取"本 DLL 自己的模块句柄"——静态函数的地址一定落在本模块里
static void rapier_anchor() {}

static bool load_rapier() {
	if (g_rap.tried) return g_rap.ok;
	g_rap.tried = true;
	// 先找本 DLL 所在目录，再退回默认搜索路径（exe 目录 / cwd / PATH）
	char self[MAX_PATH] = { 0 };
	HMODULE mod = nullptr;
	if (::GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
			(LPCSTR)&rapier_anchor, &mod) && mod != nullptr) {
		::GetModuleFileNameA(mod, self, MAX_PATH);
	}
	std::string dir;
	for (int i = (int)std::strlen(self) - 1; i >= 0; --i) {
		if (self[i] == '\\' || self[i] == '/') { dir.assign(self, (size_t)i + 1); break; }
	}
	std::string local = dir + "rapier_bridge.dll";
	g_rap.dll = ::LoadLibraryA(local.c_str());
	if (g_rap.dll == nullptr) g_rap.dll = ::LoadLibraryA("rapier_bridge.dll");
	if (g_rap.dll == nullptr) {
		printf("[RapierPhys] 加载 rapier_bridge.dll 失败（GetLastError=%lu）\n", (unsigned long)::GetLastError());
		return false;
	}
#define RP_GET(field, name) \
	g_rap.field = (decltype(g_rap.field))::GetProcAddress(g_rap.dll, name); \
	if (g_rap.field == nullptr) { printf("[RapierPhys] 缺少符号 %s\n", name); return false; }
	RP_GET(world_new, "rb_world_new")
	RP_GET(world_free, "rb_world_free")
	RP_GET(world_set_gravity, "rb_world_set_gravity")
	RP_GET(world_step, "rb_world_step")
	RP_GET(body_new, "rb_body_new")
	RP_GET(body_remove, "rb_body_remove")
	RP_GET(body_set_rects, "rb_body_set_rects")
	RP_GET(body_set_pose, "rb_body_set_pose")
	RP_GET(body_set_vel, "rb_body_set_vel")
	RP_GET(body_get_state, "rb_body_get_state")
	RP_GET(body_is_sleeping, "rb_body_is_sleeping")
	RP_GET(body_wake, "rb_body_wake")
	RP_GET(contact_count, "rb_contact_count")
	RP_GET(contact_get, "rb_contact_get")
	RP_GET(body_count, "rb_body_count")
	RP_GET(body_add_force, "rb_body_add_force")
	RP_GET(body_set_type, "rb_body_set_type")
#undef RP_GET
	g_rap.ok = true;
	printf("[RapierPhys] rapier_bridge.dll 已加载: %s\n", local.c_str());
	return true;
}

struct RapierInstance {
	RPWorld world = nullptr;
	RapierInstance() { if (load_rapier()) world = g_rap.world_new(); }
	~RapierInstance() { if (world != nullptr && g_rap.world_free != nullptr) g_rap.world_free(world); }
};

// ---- 命令流的读写（不要求对齐，全部 memcpy）----
struct CmdRd {
	const uint8_t *p = nullptr;
	size_t n = 0;
	size_t i = 0;
	bool ok = true;
	uint8_t u8() { if (i + 1 > n) { ok = false; return 0; } return p[i++]; }
	int32_t i32() { int32_t v = 0; if (i + 4 > n) { ok = false; return 0; } std::memcpy(&v, p + i, 4); i += 4; return v; }
	uint32_t u32() { return (uint32_t)i32(); }
	double f64() { double v = 0; if (i + 8 > n) { ok = false; return 0; } std::memcpy(&v, p + i, 8); i += 8; return v; }
	bool f32s(size_t count, std::vector<float> &dst) {
		dst.resize(count);
		if (i + count * 4 > n) { ok = false; return false; }
		if (count > 0) std::memcpy(dst.data(), p + i, count * 4);
		i += count * 4;
		return true;
	}
};

struct CmdWr {
	uint8_t *p = nullptr;
	size_t cap = 0;
	size_t i = 0;
	void i32(int32_t v) { if (i + 4 <= cap) std::memcpy(p + i, &v, 4); i += 4; }
	void f64(double v) { if (i + 8 <= cap) std::memcpy(p + i, &v, 8); i += 8; }
};

static void run_rapier_cmd(RapierInstance *inst, const uint8_t *in, size_t in_n,
		uint8_t *out, size_t out_cap, size_t &written) {
	CmdWr w; w.p = out; w.cap = out_cap; w.i = 0;
	if (inst == nullptr || inst->world == nullptr) { w.i32(-1); written = w.i; return; }
	RPWorld W = inst->world;
	CmdRd r; r.p = in; r.n = in_n; r.i = 0;
	static std::vector<float> rect_scratch;
	double buf[8];
	while (r.ok && r.i < r.n) {
		uint8_t op = r.u8();
		if (!r.ok) break;
		switch (op) {
			case 0: {
				g_rap.world_free(W);
				inst->world = g_rap.world_new();
				W = inst->world;
				w.i32(W != nullptr ? 0 : -1);
				break;
			}
			case 1: { double x = r.f64(), y = r.f64(); g_rap.world_set_gravity(W, x, y); break; }
			case 2: { double dt = r.f64(); g_rap.world_step(W, dt); break; }
			case 3: {
				int32_t st = r.i32(); double x = r.f64(), y = r.f64(), rot = r.f64();
				w.i32((int32_t)g_rap.body_new(W, st, x, y, rot));
				break;
			}
			case 4: { uint32_t id = r.u32(); g_rap.body_remove(W, id); break; }
			case 5: {
				uint32_t id = r.u32(); int32_t cnt = r.i32();
				if (cnt < 0) cnt = 0;
				bool got = r.f32s((size_t)cnt * 4, rect_scratch);
				double fr = r.f64();
				if (got) g_rap.body_set_rects(W, id, rect_scratch.data(), cnt, fr);
				break;
			}
			case 6: { uint32_t id = r.u32(); double x = r.f64(), y = r.f64(), rot = r.f64();
				g_rap.body_set_pose(W, id, x, y, rot); break; }
			case 7: { uint32_t id = r.u32(); double vx = r.f64(), vy = r.f64(), av = r.f64();
				g_rap.body_set_vel(W, id, vx, vy, av); break; }
			case 8: {
				uint32_t id = r.u32();
				for (int k = 0; k < 6; ++k) buf[k] = 0.0;
				int32_t rc = g_rap.body_get_state(W, id, buf);
				if (rc == 0) for (int k = 0; k < 6; ++k) buf[k] = 0.0;
				for (int k = 0; k < 6; ++k) w.f64(buf[k]);
				break;
			}
			case 9: { uint32_t id = r.u32(); w.i32(g_rap.body_is_sleeping(W, id)); break; }
			case 10: { uint32_t id = r.u32(); g_rap.body_wake(W, id); break; }
			case 11: { w.i32(g_rap.contact_count(W)); break; }
			case 12: {
				int32_t idx = r.i32();
				for (int k = 0; k < 7; ++k) buf[k] = 0.0;
				g_rap.contact_get(W, idx, buf);
				for (int k = 0; k < 7; ++k) w.f64(buf[k]);
				break;
			}
			case 13: { w.i32(g_rap.body_count(W)); break; }
			case 14: { uint32_t id = r.u32(); double fx = r.f64(), fy = r.f64(), tq = r.f64();
				g_rap.body_add_force(W, id, fx, fy, tq); break; }
			case 15: { uint32_t id = r.u32(); int32_t st = r.i32();
				g_rap.body_set_type(W, id, st); break; }
			default: break;   // 未知命令：跳过（长度未知，只能就此收尾）
		}
	}
	written = w.i;
}

static GDExtensionObjectPtr create_rapier_instance(void *p_userdata, GDExtensionBool p_notify_postinitialize) {
	GDExtensionObjectPtr obj = g_construct_object((GDExtensionConstStringNamePtr)g_sn_parent.buf);
	if (obj == nullptr) return nullptr;
	RapierInstance *d = new RapierInstance();
	g_object_set_instance(obj, (GDExtensionConstStringNamePtr)g_sn_rp_class.buf, (GDExtensionClassInstancePtr)d);
	return obj;
}

static void free_rapier_instance(void *p_userdata, GDExtensionClassInstancePtr p_instance) {
	if (p_instance != nullptr) delete (RapierInstance *)p_instance;
}

static void call_rapier_cmd(void *method_userdata, GDExtensionClassInstancePtr p_instance,
		const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count,
		GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
	if (r_error) r_error->error = GDEXTENSION_CALL_OK;
	if (p_argument_count < 2) {
		if (r_error) r_error->error = GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS;
		return;
	}
	TypeStorage in_s, tmpl_s, out_s;
	g_pba_from_variant(in_s.buf, (GDExtensionVariantPtr)p_args[0]);
	g_pba_from_variant(tmpl_s.buf, (GDExtensionVariantPtr)p_args[1]);
	const uint8_t *in = g_pba_index_const(in_s.buf, 0);
	// 输出走"按模板拷贝"这条已验证过的路（C++ 侧 resize PackedByteArray 会段错误）
	GDExtensionConstTypePtr ctor_args[1] = { tmpl_s.buf };
	g_pba_copy_ctor(out_s.buf, ctor_args);
	uint8_t *out = g_pba_index(out_s.buf, 0);
	size_t written = 0;
	if (in != nullptr && out != nullptr) {
		// 头部 8 字节：out_cap = 结果段容量，cmd_len = 命令段长度。
		// ⚠️ 拿不到 PackedByteArray 的 size（见 broadphase 那处的说明），
		//    所以长度必须由调用方写在头里，不能靠"读到越界为止"。
		int32_t out_cap = 0, cmd_len = 0;
		std::memcpy(&out_cap, in, 4);
		std::memcpy(&cmd_len, in + 4, 4);
		if (out_cap < 0) out_cap = 0;
		if (cmd_len < 0) cmd_len = 0;
		run_rapier_cmd((RapierInstance *)p_instance, in + 8, (size_t)cmd_len, out + 4, (size_t)out_cap, written);
		int32_t w32 = (int32_t)written;
		std::memcpy(out, &w32, 4);
	}
	g_pba_to_variant(r_return, out_s.buf);
	g_pba_destructor(out_s.buf);
	g_pba_destructor(tmpl_s.buf);
	g_pba_destructor(in_s.buf);
}

static void register_rapier_phys() {
	GDExtensionClassCreationInfo6 info = {};
	info.is_virtual = false;
	info.is_abstract = false;
	info.is_exposed = true;
	info.is_runtime = false;
	info.create_instance_func = create_rapier_instance;
	info.free_instance_func = free_rapier_instance;
	g_register_class6(g_library, (GDExtensionConstStringNamePtr)g_sn_rp_class.buf,
		(GDExtensionConstStringNamePtr)g_sn_parent.buf, &info);
	printf("[RapierPhys] 类已注册\n");

	GDExtensionClassMethodInfo mi = {};
	mi.name = (GDExtensionStringNamePtr)g_sn_rp_cmd.buf;
	mi.call_func = call_rapier_cmd;
	mi.ptrcall_func = nullptr;
	mi.method_flags = GDEXTENSION_METHOD_FLAG_NORMAL;
	mi.has_return_value = true;
	static GDExtensionPropertyInfo ret_info = {};
	ret_info.type = GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY;
	ret_info.name = (GDExtensionStringNamePtr)g_sn_rp_ret.buf;
	ret_info.class_name = (GDExtensionStringNamePtr)g_sn_empty_class.buf;
	ret_info.hint_string = (GDExtensionStringPtr)g_str_empty_hint;
	mi.return_value_info = &ret_info;
	mi.return_value_metadata = GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE;
	static GDExtensionPropertyInfo args[2] = {};
	args[0].type = GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY;
	args[0].name = (GDExtensionStringNamePtr)g_sn_rp_a0.buf;
	args[1].type = GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY;
	args[1].name = (GDExtensionStringNamePtr)g_sn_rp_a1.buf;
	for (int i = 0; i < 2; ++i) {
		args[i].class_name = (GDExtensionStringNamePtr)g_sn_empty_class.buf;
		args[i].hint_string = (GDExtensionStringPtr)g_str_empty_hint;
	}
	static GDExtensionClassMethodArgumentMetadata meta[2] = {
		GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE, GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE };
	mi.argument_count = 2;
	mi.arguments_info = args;
	mi.arguments_metadata = meta;
	mi.default_argument_count = 0;
	mi.default_arguments = nullptr;
	g_register_method(g_library, (GDExtensionConstStringNamePtr)g_sn_rp_class.buf, &mi);
	printf("[RapierPhys] 已注册方法 cmd\n");
}


static void initialize(void *p_userdata, GDExtensionInitializationLevel p_level) {
	if (p_level != GDEXTENSION_INITIALIZATION_SCENE) return;
	GDExtensionClassCreationInfo6 info = {};
	info.is_virtual = false;
	info.is_abstract = false;
	info.is_exposed = true;
	info.is_runtime = false;
	info.create_instance_func = create_instance;
	info.free_instance_func = free_instance;
	g_register_class6(g_library, (GDExtensionConstStringNamePtr)g_sn_class.buf,
		(GDExtensionConstStringNamePtr)g_sn_parent.buf, &info);
	printf("[FastPhys] 类已注册\n");
	register_collide_batch();
	register_broadphase();
	register_solve();
	register_rapier_phys();
}

static void deinitialize(void *p_userdata, GDExtensionInitializationLevel p_level) {
	if (p_level == GDEXTENSION_INITIALIZATION_SCENE) printf("[FastPhys] 反初始化\n");
}

extern "C" __declspec(dllexport) GDExtensionBool gdextension_init(
		GDExtensionInterfaceGetProcAddress p_get_proc_address,
		GDExtensionClassLibraryPtr p_library,
		GDExtensionInitialization *r_initialization) {
	// 无缓冲输出：崩溃时块缓冲会把日志全部吞掉，什么都看不到
	setvbuf(stdout, nullptr, _IONBF, 0);
	g_get_proc_address = p_get_proc_address;
	g_library = p_library;
	g_sn_new = (GDExtensionInterfaceStringNameNewWithUtf8Chars)p_get_proc_address("string_name_new_with_utf8_chars");
	g_register_class6 = (GDExtensionInterfaceClassdbRegisterExtensionClass6)p_get_proc_address("classdb_register_extension_class6");
	g_register_method = (GDExtensionInterfaceClassdbRegisterExtensionClassMethod)p_get_proc_address("classdb_register_extension_class_method");
	g_construct_object = (GDExtensionInterfaceClassdbConstructObject)p_get_proc_address("classdb_construct_object");
	g_object_set_instance = (GDExtensionInterfaceObjectSetInstance)p_get_proc_address("object_set_instance");
	g_str_new = (GDExtensionInterfaceStringNewWithUtf8Chars)p_get_proc_address("string_new_with_utf8_chars");
	g_get_ctor = (GDExtensionInterfaceVariantGetPtrConstructor)p_get_proc_address("variant_get_ptr_constructor");
	g_get_builtin = (GDExtensionInterfaceVariantGetPtrBuiltinMethod)p_get_proc_address("variant_get_ptr_builtin_method");
	g_get_to_type = (GDExtensionInterfaceGetVariantToTypeConstructor)p_get_proc_address("get_variant_to_type_constructor");
	g_get_from_type = (GDExtensionInterfaceGetVariantFromTypeConstructor)p_get_proc_address("get_variant_from_type_constructor");
	g_get_destructor = (GDExtensionInterfaceVariantGetPtrDestructor)p_get_proc_address("variant_get_ptr_destructor");
	g_pba_index = (GDExtensionInterfacePackedByteArrayOperatorIndex)p_get_proc_address("packed_byte_array_operator_index");
	g_pba_index_const = (GDExtensionInterfacePackedByteArrayOperatorIndexConst)p_get_proc_address("packed_byte_array_operator_index_const");
	if (!g_sn_new || !g_str_new || !g_register_class6 || !g_register_method || !g_construct_object
			|| !g_object_set_instance || !g_get_ctor || !g_pba_index || !g_pba_index_const) {
		printf("[FastPhys] 关键接口缺失\n");
		return 0;
	}
	g_sn_new((GDExtensionUninitializedStringNamePtr)g_sn_class.buf, "FastPhys");
	g_sn_new((GDExtensionUninitializedStringNamePtr)g_sn_parent.buf, "RefCounted");
	g_sn_new((GDExtensionUninitializedStringNamePtr)g_sn_method.buf, "collide_batch");
	g_sn_new((GDExtensionUninitializedStringNamePtr)g_sn_ret.buf, "contacts");
	g_sn_new((GDExtensionUninitializedStringNamePtr)g_sn_a0.buf, "pairs");
	g_sn_new((GDExtensionUninitializedStringNamePtr)g_sn_a1.buf, "shape");
	g_sn_new((GDExtensionUninitializedStringNamePtr)g_sn_a2.buf, "shape");
	g_sn_new((GDExtensionUninitializedStringNamePtr)g_sn_a3.buf, "count");
	g_sn_new((GDExtensionUninitializedStringNamePtr)g_sn_bp.buf, "broadphase");
	g_sn_new((GDExtensionUninitializedStringNamePtr)g_sn_bp0.buf, "bod");
	g_sn_new((GDExtensionUninitializedStringNamePtr)g_sn_bp1.buf, "rect");
	g_sn_new((GDExtensionUninitializedStringNamePtr)g_sn_bp2.buf, "order");
	g_sn_new((GDExtensionUninitializedStringNamePtr)g_sn_bp3.buf, "shape");
	g_sn_new((GDExtensionUninitializedStringNamePtr)g_sn_bpret.buf, "mans");
	g_sn_new((GDExtensionUninitializedStringNamePtr)g_sn_sv.buf, "solve");
	g_sn_new((GDExtensionUninitializedStringNamePtr)g_sn_sv0.buf, "bod");
	g_sn_new((GDExtensionUninitializedStringNamePtr)g_sn_sv1.buf, "mans");
	g_sn_new((GDExtensionUninitializedStringNamePtr)g_sn_sv2.buf, "shape");
	g_sn_new((GDExtensionUninitializedStringNamePtr)g_sn_svret.buf, "vel");
	g_sn_new((GDExtensionUninitializedStringNamePtr)g_sn_cw.buf, "clear_warm");
	g_sn_new((GDExtensionUninitializedStringNamePtr)g_sn_probe.buf, "warm_probe");
	g_sn_new((GDExtensionUninitializedStringNamePtr)g_sn_probe0.buf, "shape");
	g_sn_new((GDExtensionUninitializedStringNamePtr)g_sn_rp_class.buf, "RapierPhys");
	g_sn_new((GDExtensionUninitializedStringNamePtr)g_sn_rp_cmd.buf, "cmd");
	g_sn_new((GDExtensionUninitializedStringNamePtr)g_sn_rp_a0.buf, "input");
	g_sn_new((GDExtensionUninitializedStringNamePtr)g_sn_rp_a1.buf, "out_template");
	g_sn_new((GDExtensionUninitializedStringNamePtr)g_sn_rp_ret.buf, "result");
	g_sn_new((GDExtensionUninitializedStringNamePtr)g_sn_empty_class.buf, "");
	g_str_new((GDExtensionUninitializedStringPtr)g_str_empty_hint, "");
	// PackedByteArray 的构造索引 1 = 拷贝构造
	g_pba_copy_ctor = g_get_ctor(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, 1);
	g_pba_default_ctor = g_get_ctor(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, 0);
	if (!g_pba_copy_ctor || !g_pba_default_ctor) { printf("[FastPhys] 拿不到 PackedByteArray 构造函数\n"); return 0; }
	if (!g_get_builtin) { printf("[FastPhys] 缺少 variant_get_ptr_builtin_method\n"); return 0; }
	g_sn_new((GDExtensionUninitializedStringNamePtr)g_sn_resize.buf, "resize");
	g_pba_resize = g_get_builtin(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY,
		(GDExtensionConstStringNamePtr)g_sn_resize.buf, PBA_RESIZE_HASH);
	if (!g_pba_resize) { printf("[FastPhys] 拿不到 PackedByteArray.resize\n"); return 0; }
	if (!g_get_to_type || !g_get_from_type || !g_get_destructor) {
		printf("[FastPhys] 缺少 Variant 转换接口\n");
		return 0;
	}
	g_pba_from_variant = g_get_to_type(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	g_pba_to_variant = g_get_from_type(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	g_pba_destructor = g_get_destructor(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	g_int_from_variant = g_get_to_type(GDEXTENSION_VARIANT_TYPE_INT);
	g_int_destructor = g_get_destructor(GDEXTENSION_VARIANT_TYPE_INT);
	// ⚠️ variant_get_ptr_destructor 对 POD 类型（int/float…）返回 **null** —— 它们没有析构函数。
	// 所以可空项要分开判断，不能一起当"必需"。
	if (!g_pba_from_variant || !g_pba_to_variant || !g_pba_destructor || !g_int_from_variant) {
		printf("[FastPhys] Variant 转换函数解析失败: from=%p to=%p dtor=%p int_from=%p\n",
			(void *)g_pba_from_variant, (void *)g_pba_to_variant,
			(void *)g_pba_destructor, (void *)g_int_from_variant);
		return 0;
	}
	r_initialization->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;
	r_initialization->userdata = nullptr;
	r_initialization->initialize = initialize;
	r_initialization->deinitialize = deinitialize;
	printf("[FastPhys] 入口被调用，接口全部拿到\n");
	return 1;
}

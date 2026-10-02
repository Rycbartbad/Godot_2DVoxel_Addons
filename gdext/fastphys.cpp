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

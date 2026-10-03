//! Godot ↔ Rapier 的桥接层：**纯 C ABI**，Rust 侧拥有全部内存。
//!
//! 为什么是 C ABI + cdylib：
//!   · Godot 侧的 GDExtension 是 MinGW g++ 编的，Rust 是 MSVC 编的 ——
//!     跨 C++ ABI 不现实，跨 C ABI 是标准做法；
//!   · 只传基本类型与裸指针，内存一律由 Rust 分配/释放，调用方不 free 任何东西。
//!
//! 外部 id 用 u32，Rapier 侧存在 RigidBody::user_data 里 —— 这样遍历时能直接映射回来。

use rapier2d::prelude::*;
use std::collections::HashMap;

pub struct World {
    bodies: RigidBodySet,
    colliders: ColliderSet,
    ij: ImpulseJointSet,
    mj: MultibodyJointSet,
    islands: IslandManager,
    bf: BroadPhaseBvh,
    nf: NarrowPhase,
    ccd: CCDSolver,
    soft: SoftBodySet,
    pipe: PhysicsPipeline,
    params: IntegrationParameters,
    gravity: Vector,
    map: HashMap<u32, RigidBodyHandle>,
    next_id: u32,
}

impl World {
    fn new() -> Self {
        World {
            bodies: RigidBodySet::new(),
            colliders: ColliderSet::new(),
            ij: ImpulseJointSet::new(),
            mj: MultibodyJointSet::new(),
            islands: IslandManager::new(),
            bf: BroadPhaseBvh::new(),
            nf: NarrowPhase::new(),
            ccd: CCDSolver::new(),
            soft: SoftBodySet::new(),
            pipe: PhysicsPipeline::new(),
            params: IntegrationParameters::default(),
            gravity: Vector::new(0.0, 600.0),
            map: HashMap::new(),
            next_id: 1,
        }
    }
}

unsafe fn wref<'a>(w: *mut World) -> Option<&'a mut World> {
    if w.is_null() { None } else { Some(&mut *w) }
}

#[no_mangle]
pub extern "C" fn rb_world_new() -> *mut World {
    Box::into_raw(Box::new(World::new()))
}

#[no_mangle]
pub extern "C" fn rb_world_free(w: *mut World) {
    if !w.is_null() { unsafe { drop(Box::from_raw(w)); } }
}

#[no_mangle]
pub extern "C" fn rb_world_set_gravity(w: *mut World, x: f64, y: f64) {
    if let Some(w) = unsafe { wref(w) } { w.gravity = Vector::new(x as f32, y as f32); }
}

#[no_mangle]
pub extern "C" fn rb_world_step(w: *mut World, dt: f64) {
    if let Some(w) = unsafe { wref(w) } {
        w.params.dt = dt as f32;
        w.pipe.step(
            w.gravity, &w.params, &mut w.islands, &mut w.bf, &mut w.nf,
            &mut w.bodies, &mut w.colliders, &mut w.ij, &mut w.mj,
            &mut w.soft, &mut w.ccd, &(), &(),
        );
    }
}

/// 建刚体。is_static != 0 表示静态。返回外部 id（>0）。
#[no_mangle]
pub extern "C" fn rb_body_new(w: *mut World, is_static: i32, x: f64, y: f64, rot: f64) -> u32 {
    let Some(w) = (unsafe { wref(w) }) else { return 0 };
    let builder = if is_static != 0 {
        RigidBodyBuilder::fixed()
    } else {
        RigidBodyBuilder::dynamic()
    }
    .translation(Vector::new(x as f32, y as f32))
    .rotation(rot as f32);
    let h = w.bodies.insert(builder);
    let id = w.next_id;
    w.next_id += 1;
    w.bodies[h].user_data = id as u128;
    w.map.insert(id, h);
    id
}

#[no_mangle]
pub extern "C" fn rb_body_remove(w: *mut World, id: u32) {
    let Some(w) = (unsafe { wref(w) }) else { return };
    if let Some(h) = w.map.remove(&id) {
        w.bodies.remove(h, &mut w.islands, &mut w.colliders, &mut w.ij, &mut w.mj, &mut w.soft, true);
    }
}

/// 给刚体重建碰撞体：rects 是 4 个 f32 一组（局部 Rect2 的 x,y,w,h），与项目的分解结果一致。
/// 每次都先清空旧碰撞体 —— 像素破坏会让分解结果频繁变化。
#[no_mangle]
pub extern "C" fn rb_body_set_rects(w: *mut World, id: u32, rects: *const f32, count: i32, friction: f64) {
    let Some(w) = (unsafe { wref(w) }) else { return };
    let Some(&h) = w.map.get(&id) else { return };
    let old: Vec<ColliderHandle> = w.bodies[h].colliders().iter().copied().collect();
    for c in old {
        w.colliders.remove(c, &mut w.islands, &mut w.bodies, &mut w.soft, true);
    }
    if rects.is_null() || count <= 0 { return; }
    let r = unsafe { std::slice::from_raw_parts(rects, (count as usize) * 4) };
    for i in 0..count as usize {
        let (px, py, sx, sy) = (r[i * 4], r[i * 4 + 1], r[i * 4 + 2], r[i * 4 + 3]);
        w.colliders.insert_with_parent(
            ColliderBuilder::cuboid(sx * 0.5, sy * 0.5)
                .translation(Vector::new(px + sx * 0.5, py + sy * 0.5))
                .friction(friction as f32),
            h,
            &mut w.bodies,
        );
    }
}

#[no_mangle]
pub extern "C" fn rb_body_set_pose(w: *mut World, id: u32, x: f64, y: f64, rot: f64) {
    let Some(w) = (unsafe { wref(w) }) else { return };
    if let Some(&h) = w.map.get(&id) {
        w.bodies[h].set_translation(Vector::new(x as f32, y as f32), true);
        w.bodies[h].set_rotation(Rot2::new(rot as f32), true);
    }
}

#[no_mangle]
pub extern "C" fn rb_body_set_vel(w: *mut World, id: u32, vx: f64, vy: f64, ang: f64) {
    let Some(w) = (unsafe { wref(w) }) else { return };
    if let Some(&h) = w.map.get(&id) {
        w.bodies[h].set_linvel(Vector::new(vx as f32, vy as f32), true);
        w.bodies[h].set_angvel(ang as f32, true);
    }
}

/// 读回状态：out 至少 6 个 f64 —— x, y, rot, vx, vy, angvel。返回 1 表示成功。
#[no_mangle]
pub extern "C" fn rb_body_get_state(w: *mut World, id: u32, out: *mut f64) -> i32 {
    let Some(w) = (unsafe { wref(w) }) else { return 0 };
    let Some(&h) = w.map.get(&id) else { return 0 };
    if out.is_null() { return 0; }
    let b = &w.bodies[h];
    let p = b.translation();
    let v = b.linvel();
    unsafe {
        *out = p.x as f64;
        *out.add(1) = p.y as f64;
        *out.add(2) = b.rotation().angle() as f64;
        *out.add(3) = v.x as f64;
        *out.add(4) = v.y as f64;
        *out.add(5) = b.angvel() as f64;
    }
    1
}

/// 施加**持久**力与力矩（Rapier 每步之后会自己清掉，所以每子步加一次 = 持久）。
/// 项目的 accum_force 是 Box2D 那种"显式 clear_forces 才清"的模型 ——
/// 两者语义在"每子步加一次"下等价。
#[no_mangle]
pub extern "C" fn rb_body_add_force(w: *mut World, id: u32, fx: f64, fy: f64, torque: f64) {
    let Some(w) = (unsafe { wref(w) }) else { return };
    if let Some(&h) = w.map.get(&id) {
        w.bodies[h].add_force(Vector::new(fx as f32, fy as f32), true);
        if torque != 0.0 { w.bodies[h].add_torque(torque as f32, true); }
    }
}

/// 设置长度单位。
///
/// ⚠️ **这是像素世界必须设的一个参数，不设会静默地错一大片。**
/// Rapier 的 IntegrationParameters 默认按"米"调（length_unit = 1.0），
/// 而下面这**一整组**长度相关参数都是乘 length_unit 得到的：
///
///     allowed_linear_error        0.005 * u     （默认 0.005 px —— 紧到几乎为零）
///     max_corrective_velocity     3.0   * u     （默认 3 px/s —— 穿透挤出慢得离谱）
///     prediction_distance         0.02  * u     （默认 0.02 px —— 等于没有推测接触）
///     max_linear_velocity         400.0 * u     （默认 400 px/s —— **钳住所有速度**）
///     contact_recycle_distance    0.05  * u
///
/// 实测症状：自由落体的速度无论重力多大都停在 **397.68 px/s**（正好逼近 400），
/// g=900 和 g=600 给出同一个终速 —— 一眼看去很像阻尼，其实不是
/// （阻尼的终速是 g/d，会随重力变）。
///
/// 100.0 是 Rapier 文档自己给像素游戏的建议值（"100 pixels = 1 meter"）。
#[no_mangle]
pub extern "C" fn rb_world_set_length_unit(w: *mut World, unit: f64) {
    let Some(w) = (unsafe { wref(w) }) else { return };
    w.params.length_unit = unit as f32;
}

/// 单独设置**最大线速度**（归一化值）。
///
/// 为什么不直接用 length_unit 一刀切：length_unit 会同时缩放
/// allowed_linear_error / max_corrective_velocity / prediction_distance /
/// contact_recycle_distance，实测设成 100 会让 validation_dynamics 的
/// "持续力矩 60 步"变成 ω 恒为 0。像素尺度要**逐参数**处理。
///
/// Rapier 默认 normalized_max_linear_velocity = 400.0（按米调的），
/// 在像素世界里表现为"速度无论重力多大都停在 397.68 px/s"。
#[no_mangle]
pub extern "C" fn rb_world_set_max_linear_velocity(w: *mut World, v: f64) {
    let Some(w) = (unsafe { wref(w) }) else { return };
    w.params.normalized_max_linear_velocity = v as f32;
}

/// 一次性设置三个**长度相关**的归一化参数（像素尺度需要逐参数调）。
///
///   pred_dist   normalized_prediction_distance   默认 0.02 —— **推测接触距离**
///   corr_vel    normalized_max_corrective_velocity 默认 3.0 —— 穿透挤出的速度上限
///   allowed_err normalized_allowed_linear_error  默认 0.005 —— 允许的线性误差
///
/// ⚠️ 默认值全是按"米"调的。在像素世界里 prediction_distance = 0.02 px
///    等于**没有推测接触** —— 快物体直接穿过薄几何（穿模）。
///    本引擎原本的 max_speculative_margin 是 1.5 px，就是同一个机制。
#[no_mangle]
pub extern "C" fn rb_world_set_pixel_params(w: *mut World, pred_dist: f64, corr_vel: f64, allowed_err: f64) {
    let Some(w) = (unsafe { wref(w) }) else { return };
    w.params.normalized_prediction_distance = pred_dist as f32;
    w.params.normalized_max_corrective_velocity = corr_vel as f32;
    w.params.normalized_allowed_linear_error = allowed_err as f32;
}

/// 开关 CCD（对应 PWorld.ccd_enabled）。
/// ⚠️ Rapier 的 CCD **默认是关的**（逐刚体），不设的话这个开关等于被静默忽略。
/// 开关 CCD 并设置**软 CCD 预测距离**（对应 PWorld.ccd_enabled / rp_soft_ccd_prediction）。
///
/// ⚠️ Rapier 的 CCD 有四个旋钮，enable_ccd 只是其中最弱的一个：
///   · enable_ccd(bool)                逐刚体，默认 **false**
///   · set_soft_ccd_prediction(距离)   逐刚体，默认 **0.0 —— 等于关着**
///   · IntegrationParameters::max_ccd_substeps  默认 **1**（同时是全局开关，0 = 全关）
///   · IntegrationParameters::min_ccd_dt        默认 1/6000
///
/// soft_ccd_prediction 是**推测 CCD**：把碰撞体按这个距离外扩去做连续检测。
/// 它就是本引擎原本 max_speculative_margin(1.5 px) 的对应物 ——
/// 默认 0.0 意味着快物体没有任何提前量，这正是穿模的来源。
#[no_mangle]
pub extern "C" fn rb_body_set_ccd(w: *mut World, id: u32, enabled: i32, soft_pred: f64) {
    let Some(w) = (unsafe { wref(w) }) else { return };
    if let Some(&h) = w.map.get(&id) {
        w.bodies[h].enable_ccd(enabled != 0);
        w.bodies[h].set_soft_ccd_prediction(soft_pred as f32);
    }
}

/// CCD 子步上限。**它同时是全局 CCD 开关**（0 = 整个世界关掉 CCD，
/// 包括"快动态体 vs 固定碰撞体"的自动 CCD）。默认 1 太小 ——
/// 大步长（低帧率 / 帧卡顿 / 爆炸初速）下一次子步撑不住。
#[no_mangle]
pub extern "C" fn rb_world_set_ccd_substeps(w: *mut World, n: u32) {
    let Some(w) = (unsafe { wref(w) }) else { return };
    w.params.max_ccd_substeps = n as usize;
}

/// 清空累积的力与力矩。
///
/// ⚠️ 必须有这个：Rapier 的 add_force 是**跨步累积**的（直到 reset_forces），
/// 而引擎的 accum_force 是"当前总力"语义（Box2D 那种，显式 clear_forces 才清）。
/// 直接每步 add 一次会让力矩按 1+2+…+N 增长 —— 实测 60 步差 33 倍。
/// 正确做法是"先 reset 再 add"，等价于 set。
#[no_mangle]
pub extern "C" fn rb_body_reset_forces(w: *mut World, id: u32) {
    let Some(w) = (unsafe { wref(w) }) else { return };
    if let Some(&h) = w.map.get(&id) {
        w.bodies[h].reset_forces(false);
        w.bodies[h].reset_torques(false);
    }
}

/// 线性/角阻尼。Rapier 的公式是 v *= 1/(1+damping*dt)，与引擎 _integrate_forces
/// 里那两行**完全同构** —— 所以直接把引擎的值设进去就等价，不需要自己再乘一遍。
#[no_mangle]
pub extern "C" fn rb_body_set_damping(w: *mut World, id: u32, lin: f64, ang: f64) {
    let Some(w) = (unsafe { wref(w) }) else { return };
    if let Some(&h) = w.map.get(&id) {
        w.bodies[h].set_linear_damping(lin as f32);
        w.bodies[h].set_angular_damping(ang as f32);
    }
}

/// 重力缩放（对应 PBody.gravity_scale）。Rapier 是逐刚体的 —— 直接设。
#[no_mangle]
pub extern "C" fn rb_body_set_gravity_scale(w: *mut World, id: u32, scale: f64) {
    let Some(w) = (unsafe { wref(w) }) else { return };
    if let Some(&h) = w.map.get(&id) {
        w.bodies[h].set_gravity_scale(scale as f32, true);
    }
}

/// 静态 <-> 动态切换（对应 PBody.make_static / make_dynamic）。
#[no_mangle]
pub extern "C" fn rb_body_set_type(w: *mut World, id: u32, is_static: i32) {
    let Some(w) = (unsafe { wref(w) }) else { return };
    if let Some(&h) = w.map.get(&id) {
        let t = if is_static != 0 { RigidBodyType::Fixed } else { RigidBodyType::Dynamic };
        w.bodies[h].set_body_type(t, true);
    }
}

#[no_mangle]
pub extern "C" fn rb_body_is_sleeping(w: *mut World, id: u32) -> i32 {
    let Some(w) = (unsafe { wref(w) }) else { return 0 };
    match w.map.get(&id) {
        Some(&h) => if w.bodies[h].is_sleeping() { 1 } else { 0 },
        None => 0,
    }
}

#[no_mangle]
pub extern "C" fn rb_body_wake(w: *mut World, id: u32) {
    let Some(w) = (unsafe { wref(w) }) else { return };
    if let Some(&h) = w.map.get(&id) { w.bodies[h].wake_up(true); }
}

/// 接触对数量（只数有流形点的）。
#[no_mangle]
pub extern "C" fn rb_contact_count(w: *mut World) -> i32 {
    let Some(w) = (unsafe { wref(w) }) else { return 0 };
    w.nf.contact_pairs()
        .filter(|p| p.has_any_active_contact())
        .count() as i32
}

/// 读第 i 个接触对：out 至少 **8** 个 f64 ——
/// id_a, id_b, nx, ny, px, py, dist, impulse。
///
/// ⚠️ 法向与接触点都必须是**世界系**：
///   · 法向直接取 Rapier 的 \`ContactManifoldData.normal\`（它本来就是世界系）；
///   · 点要由 **collider1 的位姿**把 \`local_p1\` 变换过去 —— 它本身是 collider1 的局部坐标。
///     第一版直接把它当世界坐标输出，结果是错的（但看起来"有个数"）。
#[no_mangle]
pub extern "C" fn rb_contact_get(w: *mut World, i: i32, out: *mut f64) -> i32 {
    let Some(w) = (unsafe { wref(w) }) else { return 0 };
    if out.is_null() || i < 0 { return 0; }
    let mut k = 0i32;
    for pair in w.nf.contact_pairs() {
        if !pair.has_any_active_contact() { continue; }
        if k != i { k += 1; continue; }
        let ca = pair.collider1;
        let cb = pair.collider2;
        let ida = w.colliders[ca].parent().map(|h| w.bodies[h].user_data as u32).unwrap_or(0);
        let idb = w.colliders[cb].parent().map(|h| w.bodies[h].user_data as u32).unwrap_or(0);
        let mut n = Vector::new(0.0, 1.0);
        let mut p = Vector::new(0.0, 0.0);
        let mut d = 0.0f32;
        if let Some(m) = pair.manifolds().first() {
            n = m.data.normal;
            if let Some(pt) = m.points.first() {
                let pose = w.colliders[ca].position();
                p = pose.translation + pose.rotation * pt.local_p1;
                d = pt.dist;
            }
        }
        let imp = pair.total_impulse();
        unsafe {
            *out = ida as f64;
            *out.add(1) = idb as f64;
            *out.add(2) = n.x as f64;
            *out.add(3) = n.y as f64;
            *out.add(4) = p.x as f64;
            *out.add(5) = p.y as f64;
            *out.add(6) = d as f64;
            *out.add(7) = imp.length() as f64;
        }
        return 1;
    }
    0
}

#[no_mangle]
pub extern "C" fn rb_body_count(w: *mut World) -> i32 {
    let Some(w) = (unsafe { wref(w) }) else { return 0 };
    w.map.len() as i32
}

//! 冒烟测试：通过桥接层跑"拼接地面滑行"（幽灵碰撞）+ 角接触 + 睡眠。
//! 用的是与 C ABI **同一批** `#[no_mangle] pub extern "C"` 函数；
//! 导出符号本身由 dumpbin /exports 单独验证。
use rapier_bridge::*;

fn state(w: *mut World, id: u32) -> [f64; 6] {
    let mut o = [0.0f64; 6];
    unsafe { rb_body_get_state(w, id, o.as_mut_ptr()); }
    o
}

fn main() {
    unsafe {
        let w = rb_world_new();
        // 拼接地面：一个静态刚体，60 段 20x40
        let g = rb_body_new(w, 1, 0.0, 0.0, 0.0);
        let mut rects = Vec::new();
        for i in 0..60 {
            rects.extend_from_slice(&[i as f32 * 20.0, 0.0, 20.0, 40.0]);
        }
        rb_body_set_rects(w, g, rects.as_ptr(), 60, 0.5);
        let b = rb_body_new(w, 0, 10.0, -16.0, 0.0);
        rb_body_set_rects(w, b, [0.0f32, 0.0, 16.0, 16.0].as_ptr(), 1, 0.5);

        for _ in 0..60 { rb_world_step(w, 1.0 / 60.0); }
        let rest_y = state(w, b)[1];
        let start_x = state(w, b)[0];
        let mut prev_x = start_x;
        let (mut backwards, mut max_dy, mut max_rot) = (0, 0.0f64, 0.0f64);
        for _ in 0..600 {
            let vy = state(w, b)[4];
            rb_body_set_vel(w, b, 120.0, vy, 0.0);
            rb_world_step(w, 1.0 / 60.0);
            let s = state(w, b);
            if s[0] - prev_x < -1.0e-4 { backwards += 1; }
            max_dy = max_dy.max((s[1] - rest_y).abs());
            max_rot = max_rot.max(s[2].abs().to_degrees());
            prev_x = s[0];
        }
        println!("[冒烟] 拼接地面滑行：前进 {:.2} | 倒退 {} 次 | 最大偏离 {:.4} px | 最大转角 {:.3}°  {}",
            prev_x - start_x, backwards, max_dy, max_rot,
            if backwards == 0 && max_dy < 1.0 { "OK" } else { "**有问题**" });

        // 角接触：24x24 方块转 40°
        let w2 = rb_world_new();
        let g2 = rb_body_new(w2, 1, 0.0, 20.0, 0.0);
        rb_body_set_rects(w2, g2, [-2000.0f32, -20.0, 4000.0, 40.0].as_ptr(), 1, 0.5);
        let th = 40.0f64.to_radians();
        let low = 12.0 * (th.sin() + th.cos());
        let b2 = rb_body_new(w2, 0, 0.0, -low, th);
        rb_body_set_rects(w2, b2, [-12.0f32, -12.0, 24.0, 24.0].as_ptr(), 1, 0.5);
        for _ in 0..120 { rb_world_step(w2, 1.0 / 60.0); }
        let r1 = state(w2, b2)[2].to_degrees();
        println!("[冒烟] 角接触 40° 方块：终态 {:.3}°（转了 {:.3}°）  {}",
            r1, r1 - 40.0, if (r1 - 40.0).abs() > 20.0 { "倒了 OK" } else { "**没倒**" });

        println!("[冒烟] 刚体数 {} | 接触对数 {}", rb_body_count(w), rb_contact_count(w));
        rb_world_free(w);
        rb_world_free(w2);
    }
}

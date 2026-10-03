#!/usr/bin/env python3
"""体检 + 修复本项目**已知的几种"静默失效"状态**。

## 为什么需要它

这一轮里出现过三次"看起来完全不相干"的故障，真因都是环境状态：

1. **addon 住在项目树里** -> 它是 src/ 的逐字拷贝，.uid 完全相同 ->
   UID 冲突 -> Godot 解析不到 src/ 的脚本，报
   `Could not find script "res://src/physics/pworld.gd"`（文件明明在）。
   测试会整批"加载失败"，编辑器也打不开。

2. **.godot/extension_list.cfg 丢失** -> 扩展根本不加载 -> 物理完全不动。
   症状看起来像「重力没了」。

3. **.godot/uid_cache.bin 被污染**（addon 住过树里之后）-> 同样的
   "Could not find script"。删掉让它重建即可。

这三种都**不会**在代码里留下任何痕迹，报错也都不指向真因。

用法：
    python tools/doctor.py            # 只体检
    python tools/doctor.py --fix      # 能自动修的就修
"""
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GODOT = os.environ.get(
    "GODOT_EXE", r"D:\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe")

problems = []
fixes = []


def check(name, ok, detail="", fix=None):
    print("  %s  %s%s" % ("OK  " if ok else "**X**", name, ("  " + detail) if detail else ""))
    if not ok:
        problems.append(name)
        if fix:
            fixes.append((name, fix))


def run_editor_scan():
    """让 Godot 重新扫描项目（会重建 extension_list.cfg / uid_cache.bin）。"""
    subprocess.run([GODOT, "--headless", "--editor", "--path", str(ROOT), "--quit"],
                   cwd=str(ROOT), capture_output=True, text=True, timeout=300)


def main() -> int:
    do_fix = "--fix" in sys.argv
    print("=== 项目体检 ===")

    # 1) addon 不能住在项目树里
    addon = ROOT / "addons" / "pixel_destruction"
    check("addon 不在项目树里", not addon.exists(),
          "（它在树里会让 UID 冲突，测试整批加载失败、编辑器打不开）",
          fix=lambda: shutil.rmtree(ROOT / "addons", ignore_errors=True))

    # 2) 引擎源码在
    check("src/physics/pworld.gd 存在", (ROOT / "src" / "physics" / "pworld.gd").is_file())

    # 3) 两个动态库都在
    for d in ("fastphys.dll", "rapier_bridge.dll"):
        check("gdext/%s 存在" % d, (ROOT / "gdext" / d).is_file())

    # 4) 扩展注册表
    ext = ROOT / ".godot" / "extension_list.cfg"
    ok_ext = ext.is_file() and "fastphys.gdextension" in ext.read_text(encoding="utf-8", errors="ignore")
    check(".godot/extension_list.cfg 指向 fastphys", ok_ext,
          "（丢了的话物理完全不动，看起来像「重力没了」）",
          fix=run_editor_scan)

    # 5) UID 缓存
    check(".godot/uid_cache.bin 存在", (ROOT / ".godot" / "uid_cache.bin").is_file(),
          "（被污染后同样报 Could not find script）",
          fix=lambda: [p.unlink() for p in
                       (ROOT / ".godot" / "uid_cache.bin",
                        ROOT / ".godot" / "global_script_class_cache.cfg") if p.is_file()]
                       or run_editor_scan())

    if problems and do_fix:
        print("")
        print("=== 修复 ===")
        for name, fn in fixes:
            print("  修 %s ..." % name)
            try:
                fn()
                print("    完成")
            except Exception as e:  # noqa: BLE001
                print("    **失败: %s**" % e)
        print("")
        print("  重新体检：")
        return main_after_fix()
    if problems:
        print("")
        print("  有 %d 项异常。加 --fix 试试自动修。" % len(problems))
        return 1
    print("")
    print("  一切正常。")
    return 0


def main_after_fix() -> int:
    print("    （重跑体检）")
    subprocess.run([sys.executable, __file__], cwd=str(ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())

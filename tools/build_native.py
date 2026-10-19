#!/usr/bin/env python3
r"""构建原生动态库，并在构建前检查"编辑器是否开着"。

## 用法

    python tools/build_native.py             # Windows：gdext/fastphys.dll + rapier_bridge.dll
    python tools/build_native.py --android   # Android：gdext/<abi>/lib*.so（两个 ABI）
    python tools/build_native.py --android --out addons/pixel_destruction/native
                                             # 同上，但直接落进 addon 的 native/<abi>/

## 为什么需要这个脚本

`fastphys.dll` 和 `rapier_bridge.dll` 只要被一个运行中的 Godot 打开着，
`Copy-Item` / `g++` 就会**静默失败**（不报错、不留新文件），
而症状是"物理完全不动""所有刚体停在原点"—— 完全指不到构建问题。

这个坑踩过两次。所以把它做成一个**会吵闹地失败**的前置检查，
而不是靠人记得先关编辑器。

退出码非 0 表示没构建成（或者根本没开始构建）。

## Android 侧为什么是单独一条路

Windows 是"g++ 编 C++ + cargo 编 Rust"两条本机工具链；Android 是**交叉编译**，
两边都得换成 NDK 的 clang 和对应的 rust target。产物也不能放在 `gdext/` 根下：

  · Godot 的 Android 导出强制 .so 文件名以 "lib" 开头
    （`EditorExportPlatformAndroid::save_apk_so` 里硬性检查）；
  · 运行时 `OS_Android::open_dynamic_library` 在 `res://` 找不到该文件时，会退化成
    `dlopen(p_path.get_file())` —— **只用文件名**让 Android 的 linker 去 `lib/<abi>/` 里找。

所以两个 ABI 的 basename 必须一致（`libfastphys.so`），只能靠目录区分 ——
这就是 `gdext/arm64/` 与 `gdext/x86_64/` 的由来。

⚠️ **不要**把 rapier_bridge 静态链进 fastphys。那要 (1) 用 `-Wl,--undefined` 把每个
   rb_* 符号钉住（代码是 dlsym 按名字查的，链接器看不到引用），(2) 运行时"打开自己"
   再 dlsym（Godot 用 RTLD_LOCAL 加载扩展，glibc 的 dlsym(RTLD_DEFAULT) 搜不到）。
   `.gdextension` 的 `[dependencies]` 能把第二个 .so 直接放进 APK 的 `lib/<abi>/`，
   两个平台就共用同一条「独立库 + 运行时加载」的路 —— 见 tools/build_addon.py。

⚠️ 产物的 API 级别是 **24**（clang 的 `--target=...24` 与 Rust 侧同一条）。
   如果 Godot 项目的 minSdk 被调到 24 以下，设备上会**加载失败**（不是崩溃，是扩展没了）。

⚠️ 往 addon 里放：`--out <addon>/native` 会直接落成 `native/<abi>/lib*.so`。
   **顺序要紧**：先跑 tools/build_addon.py（它会整目录重建），再跑这条 ——
   反过来会把刚拷进去的 .so 一起删掉。
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GDEXT = ROOT / "gdext"
BRIDGE = GDEXT / "rapier_bridge"
# 构建产物放到仓库外：cargo 的 target/ 有几百 MB，不该进仓库
TARGET_DIR = Path(os.environ.get("RB_TARGET_DIR", r"D:\AI\tmp\rb_target"))

DLLS = ["fastphys.dll", "rapier_bridge.dll"]

## Android：目录名 -> (rust target, clang target)。产物落 gdext/<abi>/。
##
## ⚠️ 目录名不是 rust target 名（arm64 vs aarch64）：Godot 的 .gdextension 里用的
##    tag 是 arm64 / x86_64，构建产物按这个分目录，两边才对得上。
API_LEVEL = "24"

ANDROID_ABIS = {
    "arm64": ("aarch64-linux-android", "aarch64-linux-android" + API_LEVEL),
    "x86_64": ("x86_64-linux-android", "x86_64-linux-android" + API_LEVEL),
}


def find_ndk() -> Path:
    """找 NDK 根目录。

    ⚠️ 找不到就**响亮地退出**，不要退回去用本机 g++ —— 那会产出一个 x86_64 的
       .so 塞进 arm64 的目录，而症状是"装到手机上物理不动"，指不回来。
    """
    env = os.environ.get("ANDROID_NDK_HOME")
    if env and Path(env).is_dir():
        return Path(env)
    for base in [Path(r"D:\ink2-android\sdk\ndk"),
                 Path(os.environ.get("LOCALAPPDATA", "")) / "Android" / "Sdk" / "ndk"]:
        if base.is_dir():
            versions = sorted([p for p in base.iterdir() if p.is_dir()], reverse=True)
            if versions:
                return versions[0]
    sys.exit("找不到 NDK。设 ANDROID_NDK_HOME 指向 NDK 根目录。")


def wanted_symbols() -> list:
    """从 fastphys.cpp 里抓出真正会用到的 rb_* 符号名（跳过注释掉的那些）。

    只用于**核对**：这些符号是 dlsym 按名字查的，链接器看不到引用，少了也不会在
    链接期报错 —— 只会在运行时变成「缺少符号 xxx」。从源码反推一份清单来对账，
    能在构建阶段就抓住 Rust 侧改签名而 C++ 侧没同步。
    """
    names = []
    for raw in (GDEXT / "fastphys.cpp").read_text(encoding="utf-8").splitlines():
        # ⚠️ 先把行尾注释切掉再匹配：注释里的 RP_GET(...) 会被算成"要用到的符号"，
        #    对账就报"缺符号 xxx" —— 假阳性会把真问题淹掉（整行注释切完是空串，天然跳过）。
        line = raw.split("//", 1)[0]
        names += re.findall(r'RP_GET\(\s*\w+\s*,\s*"(rb_[A-Za-z0-9_]+)"\s*\)', line)
    return names


def build_android(out_root: Path) -> int:
    """交叉编译两个 ABI 的两个 .so 到 out_root/<abi>/。"""
    print("=== 构建 Android 原生库 ===")
    ndk = find_ndk()
    bin_dir = ndk / "toolchains" / "llvm" / "prebuilt" / "windows-x86_64" / "bin"
    if not bin_dir.is_dir():
        print("  **NDK 里找不到 clang: %s" % bin_dir)
        return 1
    print("NDK: %s" % ndk)
    print("产物目录: %s" % out_root)

    bad = 0
    # ⚠️ 与 Windows 那条路同一条规矩：**必须核对"这次真的写出来了"**。
    #    踩过的坑是"构建报告成功、文件却没更新"（当时是 DLL 被运行中的编辑器锁住），
    #    而 Android 这边更隐蔽：cargo 命中缓存 / copyfile 失败都会留下**旧** .so，
    #    症状是"以为编好了，装到手机上还是上一版的行为"。
    stamp = time.time()
    for abi, (rust_target, clang_target) in ANDROID_ABIS.items():
        print("")
        print("--- %s (%s) ---" % (abi, rust_target))
        out_dir = out_root / abi
        out_dir.mkdir(parents=True, exist_ok=True)
        out_so = out_dir / "libfastphys.so"
        out_bridge = out_dir / "librapier_bridge.so"

        # 1) Rust 桥接层
        # ⚠️ NDK 的 clang 包装器只是个 .cmd，cargo 直接当 linker 调不可靠 ——
        #    改成直接调 clang.exe，并把 --target 通过 link-arg 传进去。
        env = dict(os.environ,
                   CARGO_TARGET_DIR=str(TARGET_DIR),
                   CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER=str(bin_dir / "clang.exe"),
                   CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER=str(bin_dir / "clang.exe"),
                   RUSTFLAGS="-C link-arg=--target=%s" % clang_target)
        r = subprocess.run(["cargo", "build", "--release", "--target", rust_target, "--lib"],
                           cwd=str(BRIDGE), capture_output=True, text=True, env=env)
        if r.returncode != 0:
            print("  **cargo build 失败（%s）**" % rust_target)
            for line in (r.stdout + r.stderr).splitlines():
                if "error" in line.lower():
                    print("    " + line)
            bad += 1
            continue
        built = TARGET_DIR / rust_target / "release" / "librapier_bridge.so"
        if not built.is_file():
            print("  **找不到 %s" % built)
            bad += 1
            continue
        shutil.copyfile(built, out_bridge)

        # 2) GDExtension 入口（只有入口；桥接层是独立的 .so，走 [dependencies]）
        if not build("clang++", [
            bin_dir / "clang++.exe",
            "--target=" + clang_target,
            "-O2", "-std=c++17", "-ffp-contract=off",
            "-shared", "-fPIC",
            # 只导出显式标记的符号（FP_EXPORT = gdextension_init）。不加这条时
            # C++ 的几百个符号全是 default 可见：.so 更大、符号面更大，
            # 而"该导出的没导出"也更难看出来（下面 mm 核对会钉住入口符号）。
            "-fvisibility=hidden",
            # 自包含：不依赖 libc++_shared.so（少一个要跟着打包的库）
            "-static-libstdc++",
            "-fdata-sections", "-ffunction-sections",
            "-I", str(ROOT),
            "-o", str(out_so), str(GDEXT / "fastphys.cpp"),
            "-Wl,--gc-sections", "-Wl,-s",
            "-llog", "-ldl", "-lm",
        ], GDEXT, out_so):
            bad += 1
            continue

        # 2.5) 新鲜度：两个 .so 必须都是**这次**写出来的（见上面的 stamp）
        for p in (out_bridge, out_so):
            if not p.is_file() or p.stat().st_mtime < stamp:
                print("  **%s 不是这次构建写出来的（旧文件 / 拷贝失败）**" % p.name)
                bad += 1

        # 3) 核对：入口符号在；桥接层导出了 fastphys 会去 dlsym 的那些 rb_*
        #    ⚠️ 这些符号是**按名字查**的，少了不会在链接期报错，只会变成运行时
        #       "缺少符号 xxx"。所以从源码反推一份清单来对账，能在构建阶段就抓住
        #       Rust 侧改签名而 C++ 侧没同步。
        nm = bin_dir / "llvm-nm.exe"
        r = subprocess.run([str(nm), "-D", "--defined-only", str(out_so)],
                           capture_output=True, text=True)
        has_init = "gdextension_init" in r.stdout
        r = subprocess.run([str(nm), "-D", "--defined-only", str(out_bridge)],
                           capture_output=True, text=True)
        exported = {l.split()[-1] for l in r.stdout.splitlines() if l.split()}
        wanted = wanted_symbols()
        missing = [s for s in wanted if s not in exported]
        print("  %s  %d bytes  gdextension_init=%s" % (
            out_so.name, out_so.stat().st_size, "有" if has_init else "**缺**"))
        print("  %s  %d bytes  rb_*=%d（fastphys 要 %d）  %s" % (
            out_bridge.name, out_bridge.stat().st_size,
            len([s for s in exported if s.startswith("rb_")]), len(wanted),
            "OK" if not missing else "**缺符号: %s**" % ", ".join(missing)))
        if not has_init or missing:
            bad += 1

    print("")
    if bad:
        print("  **有 %d 项没构建成功**" % bad)
        return 1
    print("  Android 两个 ABI 都构建成功。")
    return 0


def running_godot() -> list:
    """列出正在运行的 Godot 进程（任何变体）。"""
    try:
        out = subprocess.run(
            ["powershell", "-NoProfile", "-Command",
             "Get-Process -Name 'Godot*' -ErrorAction SilentlyContinue | "
             "ForEach-Object { \"$($_.ProcessName) $($_.Id) $($_.MainWindowTitle)\" }"],
            capture_output=True, text=True, timeout=30,
        )
        return [l.strip() for l in out.stdout.splitlines() if l.strip()]
    except Exception as e:  # noqa: BLE001 - 查不到就当没有，不阻塞构建
        print("  (进程查询失败: %s，按没有处理)" % e)
        return []


def build(label: str, cmd: list, cwd: Path, out: Path) -> bool:
    """跑一条构建命令，并**用命令自己的退出码**判断成败。

    ⚠️ 不要在 PowerShell 里写成 `& cmd | Select-Object` 再读 $LASTEXITCODE ——
       那取到的是管道最后一个命令的退出码，不是构建命令的。
       曾经因此"编译成功"了一整轮，实际跑的是旧 DLL。
    """
    # ⚠️ 必须逐个 str()：Android 那条路传进来的是 Path（bin_dir / "clang++.exe"），
    #    而 str.join 只吃字符串 —— 直接 join(cmd) 会在**第一条命令**上 TypeError。
    #    Windows 那条路恰好全是字符串，所以这个坑只在 Android 上炸。
    print("  [%s] %s" % (label, " ".join(str(c) for c in cmd)))
    r = subprocess.run(cmd, cwd=str(cwd), capture_output=True, text=True)
    if r.returncode != 0:
        print("  **%s 失败（退出码 %d）**" % (label, r.returncode))
        for line in (r.stdout + r.stderr).splitlines()[:12]:
            print("    " + line)
        return False
    if not out.is_file():
        print("  **%s 报告成功，但 %s 没生成**" % (label, out.name))
        return False
    return True


def main() -> int:
    # ⚠️ 这里必须显式分派，不能靠「import 了 argparse 就当接了参数」。
    #
    # 曾经 build_android() 写好了却没有被 main() 调用，于是 --android 被静默忽略、
    # 跑的是 Windows 构建：退出码 0、打印「两个都是最新的」，但产物是 .dll，
    # 而且把 gdext/ 下的 Windows DLL 覆盖了一遍。症状是「以为编好了 Android，
    # 装到手机上却没有原生库」—— 又一次静默做错事。
    ap = argparse.ArgumentParser(
        prog="build_native.py",
        description="构建原生动态库（默认 Windows；--android 交叉编译 Android 的两个 ABI）")
    ap.add_argument("--android", action="store_true",
                    help="构建 <out>/<abi>/libfastphys.so 与 librapier_bridge.so（两个 ABI）")
    ap.add_argument("--out", default="",
                    help="Android 产物根目录（默认 gdext）。要直接放进 addon 就指到 "
                         "addons/pixel_destruction/native（**先跑 build_addon**，它会整目录重建）")
    args = ap.parse_args()

    if args.android:
        return build_android(Path(args.out) if args.out else GDEXT)
    if args.out:
        print("**--out 只对 --android 有意义**（Windows 的两个 DLL 固定落 gdext/）")
        return 2

    print("=== 构建原生库 ===")

    procs = running_godot()
    if procs:
        print("")
        print("  **Godot 正在运行，构建会静默失败 —— 已中止。**")
        for p in procs:
            print("    " + p)
        print("")
        print("  原因：运行中的 Godot 会锁住 fastphys.dll / rapier_bridge.dll，")
        print("        于是 Copy-Item / g++ 不报错但也不产出新文件。")
        print("        而症状是「物理完全不动」「所有刚体停在原点」，很难查。")
        print("")
        print("  请先关掉编辑器（或让我关），再重跑。")
        return 2

    before = {d: (GDEXT / d).stat().st_mtime if (GDEXT / d).is_file() else 0 for d in DLLS}

    # 1) Rust 桥接层
    print("[1/2] rapier_bridge（Rust + Rapier）")
    env = dict(os.environ, CARGO_TARGET_DIR=str(TARGET_DIR))
    r = subprocess.run(["cargo", "build", "--release"], cwd=str(BRIDGE),
                       capture_output=True, text=True, env=env)
    if r.returncode != 0:
        print("  **cargo build 失败**")
        for line in (r.stdout + r.stderr).splitlines():
            if "error" in line.lower():
                print("    " + line)
        return 1
    built = TARGET_DIR / "release" / "rapier_bridge.dll"
    if not built.is_file():
        print("  **找不到 %s**" % built)
        return 1
    shutil.copyfile(built, GDEXT / "rapier_bridge.dll")
    print("  -> gdext/rapier_bridge.dll  %d bytes" % (GDEXT / "rapier_bridge.dll").stat().st_size)

    # 2) GDExtension 入口
    print("[2/2] fastphys（GDExtension 入口）")
    ok = build("g++", [
        "g++", "-O2", "-std=c++17", "-ffp-contract=off", "-shared",
        # 仅静态链接 gcc/stdcpp 会漏掉 winpthread，部署到 Godot 后触发加载错误126。
        "-static", "-I..",
        "-o", "fastphys.dll", "fastphys.cpp",
    ], GDEXT, GDEXT / "fastphys.dll")
    if not ok:
        return 1

    # 3) 核对：两个文件都必须是**这次**写出来的
    print("")
    print("=== 结果 ===")
    bad = 0
    for d in DLLS:
        f = GDEXT / d
        st = f.stat()
        fresh = st.st_mtime > before[d]
        if not fresh:
            bad += 1
        print("  %-22s %10d bytes  %s  %s" % (
            d, st.st_size, time.strftime("%H:%M:%S", time.localtime(st.st_mtime)),
            "新" if fresh else "**没更新**"))
    if bad:
        print("  **有 %d 个文件没更新 —— 构建没有真正生效**" % bad)
        return 1
    print("  两个都是最新的。")
    return 0


if __name__ == "__main__":
    sys.exit(main())

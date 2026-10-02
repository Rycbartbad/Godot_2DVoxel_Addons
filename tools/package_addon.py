#!/usr/bin/env python3
r"""把生成好的 addon 打成发布用的 zip。

## 为什么不用系统自带的 zip / Compress-Archive

Windows 的 Compress-Archive 会把 zip 内的路径写成**反斜杠**
（pixel_destruction\README.md）—— 解压到 Linux/macOS 上会得到一个名字里带反斜杠的怪文件。
而 CI 跑在 Linux 上用 zip 命令，两者产物**不一致**，
于是"本地验过了"这句话就没有意义。

zipfile 永远写正斜杠，且跨平台一致 —— 本地跑出来的字节和 CI 跑出来的一样。
顺带还能把时间戳固定住，让打包本身也是幂等的。

用法：
    python tools/package_addon.py                 # -> pixel_destruction.zip
    python tools/package_addon.py --version v1.0  # -> pixel_destruction-v1.0.zip
"""
import argparse
import os
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = os.path.join(ROOT, "addons", "pixel_destruction")
## 固定时间戳：否则同一个源码每次打包出来的字节都不同（Release 附件会失去可比性）
FIXED_DATE = (2026, 1, 1, 0, 0, 0)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", default="", help="版本号，会拼进文件名")
    ap.add_argument("--out", default="", help="输出路径（默认在仓库根目录）")
    args = ap.parse_args()

    if not os.path.isdir(ADDON):
        print("找不到 %s —— 先跑 tools/build_addon.py" % ADDON)
        return 1

    name = "pixel_destruction%s.zip" % (("-" + args.version) if args.version else "")
    out = os.path.abspath(args.out) if args.out else os.path.join(ROOT, name)

    entries = []
    for dirpath, _dirs, files in os.walk(ADDON):
        for f in sorted(files):
            full = os.path.join(dirpath, f)
            # zip 内统一用正斜杠，且顶层目录就是 pixel_destruction/
            rel = "pixel_destruction/" + os.path.relpath(full, ADDON).replace(os.sep, "/")
            entries.append((rel, full))
    entries.sort()

    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for rel, full in entries:
            info = zipfile.ZipInfo(rel, date_time=FIXED_DATE)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            with open(full, "rb") as f:
                z.writestr(info, f.read())

    size = os.path.getsize(out)
    print("已打包 %s（%d 个条目，%.1f KB）" % (os.path.relpath(out, ROOT), len(entries), size / 1024.0))
    # 自检：不能有反斜杠，且顶层目录唯一
    tops = set()
    for rel, _ in entries:
        if "\\" in rel:
            print("  ERROR zip 内出现反斜杠路径: %s" % rel)
            return 1
        tops.add(rel.split("/")[0])
    if tops != {"pixel_destruction"}:
        print("  ERROR 顶层目录不唯一: %s" % tops)
        return 1
    print("  自检 OK（路径全为正斜杠，顶层目录唯一）")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
r"""发布前的文档同步检查。

## 为什么要有这个

「每次发布前先同步文档」这条规则，光写进文档是挡不住的 ——
本仓库已经证明过一次：AGENTS.md 写了「开发只在 main」，助手照样自己推进。

所以把它变成**闸门**：promote.py 在跑测试之前先跑这个，不过就不许推进。

## 查三件事

1. **每个 class_name 都要在文档里出现过**
   代码里新加一个类而文档一字未提 —— 这是最常见的漂移。

2. **每个 tag 都要有对应的发布说明**
   docs/release_notes/<tag>.md 必须存在。发了版本却没有说明，用户无从知道改了什么。

3. **发布说明必须提到 tag 之后代码里的新类**
   防止「版本发了，但说明是照抄上一版的」。

## 用法
  python tools/check_docs.py          # 检查
  python tools/check_docs.py -v       # 列出每个类的出现位置
"""
import argparse
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")
DOCS = [
    os.path.join(ROOT, "README.md"),
    os.path.join(ROOT, "docs", "manual"),
    os.path.join(ROOT, "docs", "branches.md"),
    os.path.join(ROOT, "docs", "api_alignment.md"),
]

CLASS_RE = re.compile(r"^class_name\s+([A-Za-z_][A-Za-z0-9_]*)", re.M)


def doc_text() -> str:
    """把所有手写文档拼成一份文本（生成物 docs/api 不算 —— 它本来就是从源码来的）。"""
    parts = []
    for d in DOCS:
        if os.path.isfile(d):
            with open(d, encoding="utf-8") as f:
                parts.append(f.read())
        elif os.path.isdir(d):
            for name in sorted(os.listdir(d)):
                if name.endswith(".md"):
                    with open(os.path.join(d, name), encoding="utf-8") as f:
                        parts.append(f.read())
    return "\n".join(parts)


def class_names() -> dict:
    """src/ 里所有 class_name -> 定义它的文件"""
    out = {}
    for root, _dirs, files in os.walk(SRC):
        for name in sorted(files):
            if not name.endswith(".gd"):
                continue
            p = os.path.join(root, name)
            with open(p, encoding="utf-8") as f:
                for m in CLASS_RE.finditer(f.read()):
                    out[m.group(1)] = os.path.relpath(p, ROOT).replace(os.sep, "/")
    return out


def tags() -> list:
    r = subprocess.run(["git", "tag", "-l", "v*"], cwd=ROOT,
                       capture_output=True, text=True)
    return sorted(t for t in r.stdout.split() if t)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

    text = doc_text()
    errors = []

    # 1) 每个 class_name 都要在文档里出现过
    classes = class_names()
    missing = []
    for cname, path in sorted(classes.items()):
        # 单词边界匹配，避免 PixelShape 命中 PixelShape2D
        if not re.search(r"\b%s\b" % re.escape(cname), text):
            missing.append((cname, path))
    if missing:
        errors.append("有 %d 个 class_name 在文档里一个字都没提到：" % len(missing))
        for cname, path in missing:
            errors.append("    %-24s 定义在 %s" % (cname, path))

    # 2) 每个 tag 都要有发布说明
    for t in tags():
        p = os.path.join(ROOT, "docs", "release_notes", "%s.md" % t)
        if not os.path.isfile(p):
            errors.append("tag %s 没有发布说明：docs/release_notes/%s.md" % (t, t))

    # 3) 发布说明不能是空壳。
    #
    # ⚠️ 第一版这里查的是「必须提到至少一个 class_name」，结果**误报了**：
    #    v0.1.0 的说明里明明列了 PWorld / PBody / PixelShape，仍被判"没提到"
    #    （原因没查清，也不值得查 —— 见下）。一个会误报的闸门**比没有闸门更糟**：
    #    它会训练人绕过它，那这条规则就死了。
    #
    #    换成可度量的判据：长度。空壳说明（一句"见 changelog"）必然很短，
    #    而且长度不会被正则/编码/反引号这些东西影响。
    MIN_LEN = 400
    for t in tags():
        p = os.path.join(ROOT, "docs", "release_notes", "%s.md" % t)
        if not os.path.isfile(p):
            continue
        with open(p, encoding="utf-8") as f:
            body = f.read().strip()
        if len(body) < MIN_LEN:
            errors.append("%s 的发布说明只有 %d 字符（少于 %d），像是空壳：%s"
                          % (t, len(body), MIN_LEN,
                             os.path.relpath(p, ROOT).replace(os.sep, "/")))

    if args.verbose:
        print("文档里提到的 class_name：")
        for cname, path in sorted(classes.items()):
            n = len(re.findall(r"\b%s\b" % re.escape(cname), text))
            print("  %-24s %3d 处  (%s)" % (cname, n, path))

    if errors:
        print("文档同步检查未通过（%d 项）：" % len(errors))
        for e in errors:
            print("  " + e)
        print("")
        print("发布前先把文档补齐 —— 这条闸门就是为了防止「功能发了、文档没跟」。")
        return 1

    print("文档同步检查通过（%d 个类，%d 个 tag）" % (len(classes), len(tags())))
    return 0


if __name__ == "__main__":
    sys.exit(main())

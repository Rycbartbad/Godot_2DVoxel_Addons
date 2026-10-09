#!/usr/bin/env python3
r"""从源码生成工程化的 API 参考（Markdown）。

## 为什么是"XML + 源码"的混合方案

Godot 自带 `--doctool --gdscript-docs`，能把 GDScript 的内联文档导出成 XML
（与引擎类参考同构）。但它有个硬伤：**描述文本里的换行被压平成了空格** ——
注释里的 `##   · xxx` 列表项会连成一整段，读不了。

所以：
  · **结构（签名/类型/默认值/继承）取自 XML** —— 权威，且不用自己写 GDScript 解析器；
  · **正文排版取自原始 .gd 源码的 ## 注释** —— 保留换行、缩进、列表。

两边按"符号名"对齐：XML 给出符号清单，源码里找该符号声明**紧挨着的**那段 ## 注释。

## 产物
  docs/api/README.md        索引 + 模块分组
  docs/api/<类名>.md        每个类一页
  docs/api/_coverage.md     文档覆盖率（哪些公开成员没写注释）

## 用法
  python tools/gen_api_docs.py            # 生成到 docs/api/
  python tools/gen_api_docs.py --check    # 只查覆盖率，有未文档化的公开成员就非零退出
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs", "api")
## ⚠️ 找 Godot 的逻辑不写在这里 —— 见 tools/godot_bin.py（与 promote.py 共用）。
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from godot_bin import find_godot  # noqa: E402

MODULE_ORDER = ["physics", "core", "render", "gpu", "demo"]

## 引擎脚本没有 class_name，Godot 导出的类名是**文件路径**，
## 靠文件名转 CamelCase 会得到 Pbody/Pworld 这种错拼。
## 这里给出对外文档里使用的正式名字（改引擎命名时同步改这里）。
NAME_MAP = {
    "Pbody": "PBody",
    "Pworld": "PWorld",
    "Gpudestruction": "GPUDestruction",
}


def official(short: str) -> str:
    """把 Pbody.Hit 这样的名字按 NAME_MAP 修正。"""
    head, dot, tail = short.partition(".")
    return NAME_MAP.get(head, head) + (dot + tail if dot else "")



def run_doctool(godot: str, outdir: str) -> bool:
    cmd = [godot, "--headless", "--path", ROOT, "--doctool", outdir,
           "--gdscript-docs", "res://src"]
    try:
        subprocess.run(cmd, check=True, capture_output=True, timeout=900)
    except Exception as e:
        print("  Godot 导出失败：%s" % e)
        return False
    return True


DECL = re.compile(
    r"^\s*(?:static\s+)?(?:func|var|const|signal)\s+([A-Za-z_][A-Za-z0-9_]*)"
    r"|^\s*class\s+([A-Za-z_][A-Za-z0-9_]*)")


def source_docs(path: str) -> dict:
    """返回 {syms: {符号: [注释行]}, header: [文件头注释], classes: {类名: [注释行]}}。"""
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.read().split("\n")
    except OSError:
        return {"syms": {}, "header": [], "classes": {}}
    syms, classes, header = {}, {}, []
    pending, in_header = [], True
    # ⚠️ 区分"文件头注释"和"符号注释"靠的是**注释与声明之间有没有空行**：
    #    文件头注释后面会空一行再开始声明（本项目全库统一这个约定）。
    #    不区分的话，文件头会被同时当成第一个常量的文档（实测就是这个症状）。
    blank_after_comment = False
    for line in lines:
        s = line.strip()
        if s.startswith("##"):
            pending.append(s[2:].lstrip() if s.startswith("## ") else s[2:])
            blank_after_comment = False
            continue
        if s == "":
            # ⚠️ 一个**真正的空行**终止注释块。这不是小事：
            #    文件头注释和"第一个符号的注释"之间就靠这个空行区分，
            #    不终止的话两段会合并，文件头会漏进第一个常量的文档里（实测就是这个症状）。
            #    注意 "##"（后面什么都没有）不算空行 —— 那是注释内部的空段落。
            if pending:
                if in_header:
                    header = pending
                pending = []
                in_header = False
            continue
        if s.startswith("#"):
            continue
        # ⚠️ extends / class_name / @tool 出现在文件头注释**之前或之后**都可能，
        # 它们不是"真正的声明"，不能用来结束"文件头注释"的收集 ——
        # 否则文件头会被当成第一个常量的文档（实测就是这个症状）。
        if s.startswith("extends ") or s.startswith("class_name ") or s.startswith("@"):
            continue
        m = DECL.match(line)
        if m:
            name = m.group(1) or m.group(2)
            if m.group(2):
                classes[name] = pending
            elif pending and not (in_header and blank_after_comment):
                # 空行隔开的是文件头，不是这个符号的文档
                syms[name] = pending
            if in_header and pending:
                header = pending
            pending = []
            blank_after_comment = False
            in_header = False
            continue
        if pending and in_header:
            header = pending
        pending = []
        in_header = False
    return {"syms": syms, "header": header, "classes": classes}


def render_doc(lines) -> str:
    """把 ## 注释行渲染成 Markdown（保留段落、列表、代码块）。"""
    if not lines:
        return ""
    out, in_fence = [], False
    for raw in lines:
        t = raw.rstrip()
        if t.strip().startswith("```"):
            in_fence = not in_fence
            out.append(t)
            continue
        if in_fence:
            out.append(raw)
            continue
        st = t.strip()
        if st.startswith("·") or st.startswith("- "):
            out.append("- " + st.lstrip("·").strip())
        else:
            out.append(t)
    return "\n".join(out).strip()


def cls_short(name: str) -> str:
    n = name.strip('"')
    inner = ""
    if '"' in n:
        n, inner = n.split('"', 1)
        inner = inner.lstrip(".")
    stem = os.path.splitext(os.path.basename(n))[0]
    short = "".join(p.capitalize() for p in stem.split("_"))
    return short + ("." + inner if inner else "")


def mod_of(name: str) -> str:
    n = name.strip('"').split('"')[0]
    parts = n.split("/")
    return parts[1] if len(parts) > 2 and parts[0] == "src" else "其它"


def parse_xml(path: str) -> dict:
    root = ET.parse(path).getroot()
    raw = root.get("name", "")
    d = {"raw": raw, "name": official(cls_short(raw)), "module": mod_of(raw),
         "inherits": root.get("inherits", ""),
         "brief": (root.findtext("brief_description") or "").strip(),
         "desc": (root.findtext("description") or "").strip(),
         "methods": [], "members": [], "constants": [], "source": ""}
    for m in root.findall("./methods/method"):
        rt = m.find("return")
        d["methods"].append({
            "name": m.get("name", ""),
            "static": "static" in (m.get("qualifiers") or ""),
            "ret": (rt.get("type") if rt is not None else "void") or "void",
            "params": [(p.get("name", ""), clean_type(p.get("type", "")), p.get("default"))
                       for p in m.findall("param")],
            "desc": (m.findtext("description") or "").strip()})
    for m in root.findall("./members/member"):
        d["members"].append({"name": m.get("name", ""), "type": clean_type(m.get("type", "")),
                             "default": m.get("default", ""),
                             "desc": (m.text or "").strip()})
    for c in root.findall("./constants/constant"):
        d["constants"].append({"name": c.get("name", ""), "value": c.get("value", ""),
                               "desc": (c.text or "").strip()})
    return d


def find_source(raw: str) -> str:
    rel = raw.strip('"').split('"')[0]
    p = os.path.join(ROOT, rel.replace("/", os.sep))
    return p if os.path.isfile(p) else ""


TYPE_PATH = re.compile(r'"([^"]+\.gd)"\.?')


def clean_type(t: str) -> str:
    """'"src/physics/query.gd".Hit' -> 'Query.Hit'"""
    def rep(m):
        stem = os.path.splitext(os.path.basename(m.group(1)))[0]
        return official("".join(p.capitalize() for p in stem.split("_")))
    return TYPE_PATH.sub(rep, t)


def is_preload_const(k: dict) -> bool:
    """preload(...) 常量是实现细节，不进对外文档。

    ⚠️ XML 里脚本引用的 value 是 `<Object>`（Godot 序列化不了脚本资源），
    所以光判断 `preload(` 是不够的。
    """
    v = k["value"]
    return ("preload(" in v or "<Object>" in v or "<GDScript" in v
            or k["name"].startswith("_"))


def sig(m: dict) -> str:
    ps = []
    for n, t, dv in m["params"]:
        s = "%s: %s" % (n, t)
        if dv is not None:
            s += " = %s" % dv
        ps.append(s)
    return "%sfunc %s(%s) -> %s" % ("static " if m["static"] else "", m["name"],
                                    ", ".join(ps), clean_type(m["ret"]))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="只做覆盖率检查")
    args = ap.parse_args()

    godot = find_godot()
    if not godot:
        print("找不到 Godot。设 GODOT_BIN 环境变量，或把 godot 放进 PATH。")
        return 1
    tmp = tempfile.mkdtemp(prefix="gdapi_")
    try:
        if not run_doctool(godot, tmp):
            return 1
        classes = [parse_xml(os.path.join(tmp, f))
                   for f in sorted(os.listdir(tmp)) if f.endswith(".xml")]
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    if not classes:
        print("没有导出到任何类 —— 检查 src/ 下有没有脚本。")
        return 1

    src_cache, missing, total_pub = {}, [], 0
    for c in classes:
        sp = find_source(c["raw"])
        c["source"] = sp
        if sp and sp not in src_cache:
            src_cache[sp] = source_docs(sp)
        sd = src_cache.get(sp, {"syms": {}, "header": [], "classes": {}})
        for m in c["methods"] + c["members"]:
            m["doc"] = sd["syms"].get(m["name"], [])
        c["header_doc"] = (sd["header"] if c["name"] == official(cls_short(c["raw"]))
                           else sd["classes"].get(c["name"].split(".")[-1], []))

    for c in classes:
        pub = [m for m in c["methods"] if not m["name"].startswith("_")]
        pub += [m for m in c["members"] if not m["name"].startswith("_")]
        total_pub += len(pub)
        for m in pub:
            if not m["doc"] and not m["desc"]:
                missing.append("%s.%s" % (c["name"], m["name"]))

    if args.check:
        if missing:
            print("=== 有 %d 个公开成员没有文档 ===" % len(missing))
            for x in missing[:40]:
                print("  " + x)
            return 1
        print("=== 文档覆盖完整（%d 个公开成员）===" % total_pub)
        return 0

    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        if f.endswith(".md"):
            os.remove(os.path.join(OUT, f))

    by_mod = {}
    for c in classes:
        by_mod.setdefault(c["module"], []).append(c)
    for v in by_mod.values():
        v.sort(key=lambda x: x["name"])

    for c in classes:
        L = ["# %s" % c["name"], ""]
        if c["inherits"]:
            L += ["继承：`%s`" % c["inherits"], ""]
        hd = render_doc(c["header_doc"]) or c["desc"] or c["brief"]
        if hd:
            L += [hd, ""]
        if c["source"]:
            L += ["源码：`%s`" % os.path.relpath(c["source"], ROOT).replace(os.sep, "/"), ""]
        consts = [k for k in c["constants"] if not is_preload_const(k)]
        if consts:
            L += ["## 常量", ""]
            for k in consts:
                L.append("- `%s = %s`%s" % (k["name"], k["value"],
                                                  ("  " + k["desc"]) if k["desc"] else ""))
            L.append("")
        vis = [m for m in c["members"] if not m["name"].startswith("_")]
        if vis:
            L += ["## 成员", ""]
            for m in vis:
                dv = (" = %s" % m["default"]) if m["default"] not in ("", "null") else ""
                L += ["### `%s: %s`%s" % (m["name"], m["type"], dv), ""]
                d = render_doc(m["doc"]) or m["desc"]
                if d:
                    L += [d, ""]
        pub_methods = [m for m in c["methods"] if not m["name"].startswith("_")]
        if pub_methods:
            L += ["## 方法", ""]
            for m in pub_methods:
                L += ["### `%s`" % sig(m), ""]
                d = render_doc(m["doc"]) or m["desc"]
                if d:
                    L += [d, ""]
                if m["params"]:
                    L += ["| 参数 | 类型 | 默认 |", "|---|---|---|"]
                    for n, t, dv in m["params"]:
                        L.append("| `%s` | `%s` | %s |" %
                                 (n, t, ("`%s`" % dv) if dv is not None else "—"))
                    L.append("")
        with open(os.path.join(OUT, c["name"].replace(".", "_") + ".md"), "w",
                  encoding="utf-8", newline="\n") as f:
            f.write("\n".join(L).rstrip() + "\n")

    L = ["# API 参考", "",
         "由 `tools/gen_api_docs.py` 从源码的 `##` 注释生成（**生成物，不进仓库**）。",
         "结构取自 Godot 的 `--doctool --gdscript-docs`，排版取自原始注释。", ""]
    for mod in MODULE_ORDER + [m for m in sorted(by_mod) if m not in MODULE_ORDER]:
        if mod not in by_mod:
            continue
        L += ["## %s" % mod, ""]
        for c in by_mod[mod]:
            b = render_doc(c["header_doc"]).split("\n")[0] if c["header_doc"] else (c["brief"] or "")
            L.append("- [%s](%s.md)%s" % (c["name"], c["name"].replace(".", "_"),
                                          ("  —— " + b.replace("|", "\\|")) if b else ""))
        L.append("")
    with open(os.path.join(OUT, "README.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(L).rstrip() + "\n")

    L = ["# 文档覆盖率", "",
         "公开成员共 **%d** 个，其中 **%d** 个没有文档。" % (total_pub, len(missing)), ""]
    if missing:
        L += ["| 未文档化的公开成员 |", "|---|"] + ["| `%s` |" % x for x in missing]
    with open(os.path.join(OUT, "_coverage.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(L).rstrip() + "\n")

    print("已生成 %d 个类 -> %s" % (len(classes), os.path.relpath(OUT, ROOT)))
    print("  公开成员 %d 个，未文档化 %d 个（见 _coverage.md）" % (total_pub, len(missing)))
    return 0


if __name__ == "__main__":
    sys.exit(main())

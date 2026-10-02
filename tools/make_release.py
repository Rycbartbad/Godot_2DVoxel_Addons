#!/usr/bin/env python3
r"""用 GitHub API 建 Release（从仓库里的发布说明读正文）。

## 为什么单独写这个脚本

tag 用 git 推就够了，但 **Release 是 GitHub 的元数据**，git 推不上去，
必须走 API。而 API 需要 token —— 这个脚本把 token 的读取、仓库地址解析、
正文装配都封起来，让"发一个版本"变成一条命令。

## token 放哪（**不要**贴进对话或写进仓库）

脚本按顺序找：

  1. 环境变量 GITHUB_TOKEN 或 GH_TOKEN
  2. 文件 ~/.gh_token（内容就是 token 本身，一行）

推荐用文件：

  # 在 GitHub 建 token： https://github.com/settings/tokens
  #   经典 token 勾 repo
  #   细粒度 token 给 Contents: Read and write
  # 然后（PowerShell，注意别让内容进 shell 历史）：
  Set-Content -Path "$env:USERPROFILE\.gh_token" -Value "ghp_xxxx" -NoNewline

脚本**从不打印 token**，出错信息里也会把它抹掉。

## 用法

  python tools/make_release.py v0.2.0              # 建 Release
  python tools/make_release.py v0.2.0 --dry-run    # 只显示将要提交的内容
  python tools/make_release.py v0.2.0 --draft      # 建草稿
"""
import argparse
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
API = "https://api.github.com"


def token() -> str:
    for n in ("GITHUB_TOKEN", "GH_TOKEN"):
        v = os.environ.get(n)
        if v:
            return v.strip()
    p = os.path.join(os.path.expanduser("~"), ".gh_token")
    if os.path.isfile(p):
        with open(p, encoding="utf-8") as f:
            return f.read().strip()
    return ""


def repo_slug() -> str:
    """从 origin 的 URL 解析出 owner/repo（SSH 与 HTTPS 两种都支持）。"""
    url = subprocess.run(["git", "remote", "get-url", "origin"], cwd=ROOT,
                         capture_output=True, text=True).stdout.strip()
    m = re.search(r"github\.com[:/]([^/]+)/(.+?)(?:\.git)?$", url)
    if not m:
        print("解析不出 GitHub 仓库地址：%s" % url)
        sys.exit(1)
    return "%s/%s" % (m.group(1), m.group(2))


def scrub(s: str, tok: str) -> str:
    """任何输出前都过一遍，确保 token 不会被打印出来。"""
    return s.replace(tok, "***") if tok else s


def call(method: str, path: str, tok: str, body=None):
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method)
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("Authorization", "Bearer " + tok)
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.loads(r.read().decode("utf-8")), None
    except urllib.error.HTTPError as e:
        return None, "%s %s" % (e.code, e.read().decode("utf-8", "replace")[:400])
    except Exception as e:                      # noqa: BLE001
        return None, str(e)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("tag")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--draft", action="store_true")
    ap.add_argument("--prerelease", action="store_true")
    args = ap.parse_args()

    tag = args.tag
    slug = repo_slug()

    # 正文优先读仓库里的发布说明 —— 让"仓库文档"和"Release 页面"同源，
    # 而不是两边各写一遍然后慢慢漂移。
    notes_path = os.path.join(ROOT, "docs", "release_notes", "%s.md" % tag)
    if os.path.isfile(notes_path):
        with open(notes_path, encoding="utf-8") as f:
            body = f.read()
        print("正文来自 %s（%d 字符）" % (
            os.path.relpath(notes_path, ROOT).replace(os.sep, "/"), len(body)))
    else:
        body = "见仓库 docs/release_notes/%s.md" % tag
        print("⚠️ 找不到 docs/release_notes/%s.md，用占位正文" % tag)

    tok = token()
    if not tok and not args.dry_run:
        print("找不到 token。请把 Personal Access Token 存到 ~/.gh_token，")
        print("或设环境变量 GITHUB_TOKEN。详见本文件开头的说明。")
        return 1

    payload = {
        "tag_name": tag,
        "name": tag,
        "body": body,
        "draft": args.draft,
        "prerelease": args.prerelease,
    }

    if args.dry_run:
        print("仓库：%s" % slug)
        print("POST %s/repos/%s/releases" % (API, slug))
        print("tag_name=%s draft=%s prerelease=%s" % (tag, args.draft, args.prerelease))
        print("正文前 300 字符：\n%s" % body[:300])
        return 0

    # 先确认 tag 在远端存在 —— 否则 API 会自己从默认分支造一个 tag，
    # 那是指向错误提交的 Release，比失败更糟。
    _, err = call("GET", "/repos/%s/git/ref/tags/%s" % (slug, tag), tok)
    if err:
        print("远端没有 tag %s，请先 git push origin %s" % (tag, tag))
        print("  " + scrub(err, tok))
        return 1

    data, err = call("POST", "/repos/%s/releases" % slug, tok, payload)
    if err:
        print("建 Release 失败：")
        print("  " + scrub(err, tok))
        return 1
    print("Release 已建立：%s" % data.get("html_url", "(无 URL)"))
    return 0


if __name__ == "__main__":
    sys.exit(main())

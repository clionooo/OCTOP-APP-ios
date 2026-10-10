#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""通过 GitHub REST API 提交本地 git 工作区的文件（绕开 git https 通道）。

用法: python push_via_api.py <repo_dir> <owner/repo> <branch> <token> <commit_message>
读取 `git ls-files` 的清单，把每个文件的当前内容建成 blob，基于远端 HEAD 的 tree 提交。
"""
import base64
import json
import os
import subprocess
import sys
import urllib.request

API = "https://api.github.com"


def api(method, url, token, payload=None):
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(API + url, data=data, method=method)
    req.add_header("Authorization", "token " + token)
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("User-Agent", "octop-ios-pusher")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=60) as resp:
        body = resp.read()
        return resp.status, (json.loads(body) if body else None)


def main():
    repo_dir, slug, branch, token, message = sys.argv[1:6]
    os.chdir(repo_dir)

    files = subprocess.check_output(["git", "ls-files"], text=True).split()
    files = [f for f in files if os.path.isfile(f)]
    print("tracked files:", len(files))

    status, ref = api("GET", "/repos/%s/git/ref/heads/%s" % (slug, branch), token)
    base_commit = ref["object"]["sha"]
    status, base = api("GET", "/repos/%s/git/commits/%s" % (slug, base_commit), token)
    base_tree = base["tree"]["sha"]
    print("remote HEAD:", base_commit[:10], "tree:", base_tree[:10])

    tree = []
    for path in files:
        with open(path, "rb") as fh:
            raw = fh.read()
        data = base64.b64encode(raw).decode("ascii")
        status, blob = api("POST", "/repos/%s/git/blobs" % slug, token,
                           {"content": data, "encoding": "base64"})
        tree.append({"path": path, "mode": "100644", "type": "blob", "sha": blob["sha"]})
        print("  blob", path, blob["sha"][:8])

    status, new_tree = api("POST", "/repos/%s/git/trees" % slug, token,
                           {"base_tree": base_tree, "tree": tree})
    print("tree:", new_tree["sha"][:10])

    status, commit = api("POST", "/repos/%s/git/commits" % slug, token,
                         {"message": message, "tree": new_tree["sha"], "parents": [base_commit]})
    print("commit:", commit["sha"][:10])

    status, _ = api("PATCH", "/repos/%s/git/refs/heads/%s" % (slug, branch), token,
                    {"sha": commit["sha"], "force": False})
    print("pushed:", commit["sha"][:10], "->", slug + "@" + branch)


if __name__ == "__main__":
    main()

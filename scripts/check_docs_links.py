#!/usr/bin/env python3
"""Link checker for tracked markdown files in this repository.

Scans every tracked .md file, resolves relative link targets against the
containing file, and reports targets that do not exist.  Existence is
checked against the working tree AND the git index, so sparse checkouts
(unmaterialized files) do not produce false positives.

Usage:  python scripts/check_docs_links.py

Introduced with the 2026-10-25 docs/ reorganization; see docs/README.md
section 4 for the maintenance rule that requires it.
"""
import collections
import os
import re
import subprocess

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

LINK = re.compile(
    r"\[[^\]]*\]\(\s*<?([^)<>\s]+?)>?(?:\s+\"[^\"]*\")?\s*\)"
)


def git(*args):
    return subprocess.run(
        ["git", "-C", REPO, *args], capture_output=True, check=True
    ).stdout


def tracked_md():
    return [p.decode("utf-8") for p in git("ls-files", "-z", "*.md").split(b"\0") if p]


def tracked_set():
    return {p.decode("utf-8") for p in git("ls-files", "-z").split(b"\0") if p}


def check():
    tracked = tracked_set()

    def exists(rel_path):
        if rel_path in tracked or os.path.exists(os.path.join(REPO, rel_path)):
            return True
        prefix = rel_path if rel_path.endswith("/") else rel_path + "/"
        return any(f.startswith(prefix) for f in tracked)

    broken = collections.defaultdict(list)
    total = ok = 0
    for f in tracked_md():
        path = os.path.join(REPO, f)
        if not os.path.exists(path):
            print(f"  SKIP (tracked but absent on disk): {f}")
            continue
        try:
            text = open(path, encoding="utf-8").read()
        except UnicodeDecodeError:
            continue
        for m in LINK.finditer(text):
            target = m.group(1).strip()
            total += 1
            if target.startswith(("http://", "https://", "mailto:", "#")):
                continue
            rel = target.split("#", 1)[0]
            if not rel:
                continue
            full = os.path.normpath(os.path.join(os.path.dirname(f), rel))
            if full.startswith(".."):
                broken[f].append(target + "  [escapes repo root]")
                continue
            if exists(full):
                ok += 1
            else:
                broken[f].append(target)
    print(f"links scanned: {total}, resolved: {ok}, broken: {total - ok}")
    for f in sorted(broken):
        for t in broken[f]:
            print(f"  BROKEN  {f}  ->  {t}")
    return broken


if __name__ == "__main__":
    check()

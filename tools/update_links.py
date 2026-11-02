#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
把 data/friend-links.json 渲染进所有页面的友情链接区块。

用法（在站点根目录执行）：
    python tools/update_links.py          # 更新所有页面
    python tools/update_links.py --check  # 只检查是否与数据源一致，不写入

页面里的占位标记不要删除、不要改名：
    <!-- FRIEND-LINKS:START -->
    ...
    <!-- FRIEND-LINKS:END -->
"""
import argparse
import html
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA_FILE = ROOT / "data" / "friend-links.json"

PATTERN = re.compile(
    r"(?P<ws>^[ \t]*)<!-- FRIEND-LINKS:START -->.*?<!-- FRIEND-LINKS:END -->",
    re.S | re.M,
)


def render_block(data, ws):
    indent = ws
    links = data.get("links", [])

    rows = []
    for item in links:
        name = html.escape(str(item.get("name", "")).strip())
        url = html.escape(str(item.get("url", "")).strip(), quote=True)
        if not name or not url:
            continue
        rows.append('%s    <li><a href="%s" target="_blank" rel="noopener">%s</a></li>' % (indent, url, name))

    if not rows:
        rows.append('%s    <li class="fl-empty">友链虚位以待，欢迎交换</li>' % indent)

    contact = str(data.get("contact_html", "")).strip()
    lines = [
        indent + "<!-- FRIEND-LINKS:START -->",
        indent + '<div class="friend-links">',
        indent + "  <h2>友情链接</h2>",
        indent + '  <ul class="fl-list">',
        "\n".join(rows),
        indent + "  </ul>",
    ]
    if contact:
        lines.append('%s  <p class="fl-contact">%s</p>' % (indent, contact))
    lines += [
        indent + "</div>",
        indent + "<!-- FRIEND-LINKS:END -->",
    ]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="同步友情链接到所有页面")
    parser.add_argument("--check", action="store_true", help="只检查，不写入")
    args = parser.parse_args()

    if not DATA_FILE.exists():
        print("找不到数据文件：%s" % DATA_FILE)
        return 1

    data = json.loads(DATA_FILE.read_text(encoding="utf-8"))
    link_count = len(data.get("links", []))

    changed, skipped = [], []
    for page in sorted(ROOT.glob("*.html")):
        text = page.read_text(encoding="utf-8")
        match = PATTERN.search(text)
        if not match:
            skipped.append(page.name)
            continue
        new = PATTERN.sub(lambda m: render_block(data, m.group("ws")), text)
        if new == text:
            continue
        if args.check:
            changed.append(page.name)
        else:
            page.write_text(new, encoding="utf-8")
            changed.append(page.name)

    if args.check:
        if changed:
            print("以下页面与数据源不一致（运行 python tools/update_links.py 同步）：")
            for name in changed:
                print("  - %s" % name)
            return 1
        print("所有页面均与数据源一致（友链 %d 条）。" % link_count)
        return 0

    if changed:
        print("已更新 %d 个页面（友链 %d 条）：" % (len(changed), link_count))
        for name in changed:
            print("  - %s" % name)
    else:
        print("没有需要更新的页面（友链 %d 条）。" % link_count)
    if skipped:
        print("跳过（无友链标记、保持原样）：%s" % "、".join(skipped))
    return 0


if __name__ == "__main__":
    sys.exit(main())

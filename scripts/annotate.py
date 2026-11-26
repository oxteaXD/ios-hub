#!/usr/bin/env python3
"""把一个文本文件的内容作为标注发到 GitHub Actions 的运行页面上。

运行页面上的摘要和日志要登录才看得到，标注（Annotations）不用，所以把最要紧的结果——
编译报错、界面测试结果——再发一份到标注里。不在 GitHub Actions 里运行时什么都不做。

一条标注的内容超过大约 4 KB 就会被平台截断，所以内容长的时候拆成几条，标题后面带上「（第几条/共几条）」。

用法：python3 scripts/annotate.py <error|warning|notice> <标题> <文件> [最多多少行，默认 80]

只依赖标准库。
"""
from __future__ import annotations

import os
import sys

# 单行太长的话截断。
MAX_LINE_LENGTH = 300
# 每条标注内容的上限（UTF-8 字节数），比平台的限制留出余量。
MAX_CHUNK_BYTES = 3400
# 平台对同一步骤里同一级别的标注有条数限制，超出的不显示。
MAX_CHUNKS = 8


def escape_data(text: str) -> str:
    return text.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def escape_property(text: str) -> str:
    return escape_data(text).replace(":", "%3A").replace(",", "%2C")


def split_into_chunks(lines: list[str]) -> list[list[str]]:
    chunks: list[list[str]] = []
    current: list[str] = []
    size = 0
    for line in lines:
        cost = len(line.encode("utf-8")) + 1
        if current and size + cost > MAX_CHUNK_BYTES:
            chunks.append(current)
            current, size = [], 0
        current.append(line)
        size += cost
    if current:
        chunks.append(current)
    return chunks


def main() -> int:
    if os.environ.get("GITHUB_ACTIONS") != "true":
        return 0
    if len(sys.argv) < 4:
        print("用法：annotate.py <error|warning|notice> <标题> <文件> [最多多少行]", file=sys.stderr)
        return 2
    level, title, path = sys.argv[1], sys.argv[2], sys.argv[3]
    limit = int(sys.argv[4]) if len(sys.argv) > 4 else 80

    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            lines = handle.read().splitlines()
    except OSError:
        return 0
    lines = [line[:MAX_LINE_LENGTH] for line in lines[:limit]]
    if not any(line.strip() for line in lines):
        return 0

    chunks = split_into_chunks(lines)
    dropped = max(len(chunks) - MAX_CHUNKS, 0)
    chunks = chunks[:MAX_CHUNKS]
    for index, chunk in enumerate(chunks, start=1):
        label = title if len(chunks) == 1 else "{}（{}/{}）".format(title, index, len(chunks))
        if dropped and index == len(chunks):
            chunk = chunk + ["（后面还有 {} 段没有列出）".format(dropped)]
        command = "::{} title={}::{}\n".format(level, escape_property(label), escape_data("\n".join(chunk)))
        sys.stdout.buffer.write(command.encode("utf-8"))
    sys.stdout.buffer.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())

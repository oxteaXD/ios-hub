#!/usr/bin/env python3
"""把一个文本文件的内容作为一条标注发到 GitHub Actions 的运行页面上。

运行页面上的摘要和日志要登录才看得到，标注（Annotations）不用，所以把最要紧的结果——
编译报错、界面测试结果——再发一份到标注里。不在 GitHub Actions 里运行时什么都不做。

用法：python3 scripts/annotate.py <error|warning|notice> <标题> <文件> [最多多少行，默认 80]

只依赖标准库。
"""
from __future__ import annotations

import os
import sys

# 单行太长的话截断，免得一条标注超出平台的长度限制。
MAX_LINE_LENGTH = 300


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

    # 工作流命令里，内容部分的百分号、回车、换行要转义；标题里的冒号和逗号也要。
    message = "\n".join(lines).replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    title = title.replace("%", "%25").replace(":", "%3A").replace(",", "%2C")
    sys.stdout.buffer.write("::{} title={}::{}\n".format(level, title, message).encode("utf-8"))
    sys.stdout.buffer.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())

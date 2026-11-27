#!/usr/bin/env python3
"""把云端构建出来的未签名安装包发成 GitHub 上的一个发行版（Release）。

由工作流里的「发布到发行版」作业调用。那个作业排在编译和界面测试之后，两个都通过才会跑到这里。
每次构建一个发行版，旧的不删。标签是「v版本号-构建号」，比如 v2026.11.27-17；
安装包在发行版里的名字固定是 Hub.ipa，所以「最新一版」有一个不变的下载地址。

做的事：

1. 从安装包里读出版本号和构建号。以包里实际写的为准，不另外传参，
   这样标签和装到设备上之后显示的版本一定对得上。
2. 生成发行说明：版本、校验和、对应的提交、三个上游各自的版本和提交、自上一个发行版以来的提交。
3. 用 gh 创建发行版并把安装包传上去。同一个标签的发行版已经有了（重跑同一次构建）就替换里面的安装包；
   标签已经指向别的提交时不动它，直接报错——已经发出去的版本不能被盖掉。

用法：
    python3 scripts/publish_release.py <Hub.ipa，或者放着它的目录> [--dry-run]

--dry-run 只把标签、标题和发行说明打印出来，什么都不创建，在自己的机器上也能跑。

只依赖标准库。真正发布时还需要 git 和 gh（GitHub 托管的运行器上都自带），以及环境变量 GH_TOKEN。
"""
from __future__ import annotations

import hashlib
import json
import os
import plistlib
import re
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "build" / "release"

# 版本号和构建号会拼进标签名，所以只接受数字和点。
VERSION_PATTERN = re.compile(r"[0-9]+(?:\.[0-9]+){0,3}")
BUILD_PATTERN = re.compile(r"[0-9]+")
# 本脚本发出来的标签：v版本号-构建号。
TAG_PATTERN = re.compile(r"v[0-9]+(?:\.[0-9]+){0,3}-([0-9]+)")
# 发行说明里最多列多少条提交。
MAX_COMMITS = 40


class ReleaseError(Exception):
    """发布不下去时抛出，内容是给人看的说明。"""


# ---------------------------------------------------------------------------
# 外部命令
# ---------------------------------------------------------------------------

def git(*args: str) -> str:
    result = subprocess.run(["git", *args], cwd=ROOT, capture_output=True)
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", "replace").strip()
        raise ReleaseError("git {} 失败：{}".format(" ".join(args), detail))
    return result.stdout.decode("utf-8", "replace")


def gh(*args: str) -> str:
    """运行 gh，返回它的标准输出。凭据在环境变量 GH_TOKEN 里，不经过命令行。"""
    try:
        result = subprocess.run(["gh", *args], cwd=ROOT, capture_output=True)
    except FileNotFoundError:
        raise ReleaseError("找不到 gh 命令") from None
    stdout = result.stdout.decode("utf-8", "replace").strip()
    stderr = result.stderr.decode("utf-8", "replace").strip()
    if result.returncode != 0:
        raise ReleaseError("gh {} 失败（退出码 {}）：\n{}".format(
            " ".join(args[:3]), result.returncode, "\n".join(part for part in (stdout, stderr) if part)))
    if stderr:
        print(stderr)
    return stdout


def annotate(level: str, title: str, lines: list[str]) -> None:
    """把结果另发一份到运行页面的标注里：日志要登录才看得到，标注不用。不在云端运行时什么都不做。"""
    OUTPUT.mkdir(parents=True, exist_ok=True)
    path = OUTPUT / "annotation.txt"
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    sys.stdout.flush()
    subprocess.run(
        [sys.executable, "-I", str(ROOT / "scripts" / "annotate.py"), level, title, str(path), "40"],
        check=False,
    )


# ---------------------------------------------------------------------------
# 安装包
# ---------------------------------------------------------------------------

def locate_ipa(argument: str) -> Path:
    """参数可以是安装包本身，也可以是放着它的目录（取回构建产物的那一步给的是目录）。"""
    path = Path(argument).resolve()
    if path.is_dir():
        found = sorted(path.rglob("*.ipa"))
        if len(found) != 1:
            raise ReleaseError("{} 里应当正好有一个 .ipa，实际找到 {} 个：{}".format(
                path, len(found), "、".join(item.name for item in found) or "（没有）"))
        path = found[0]
    if not path.is_file():
        raise ReleaseError("找不到安装包 {}".format(path))
    if path.suffix != ".ipa":
        raise ReleaseError("{} 不是 .ipa 文件".format(path.name))
    return path


def read_bundle_info(ipa: Path) -> dict:
    """读安装包里 App 的 Info.plist（编译后是二进制格式，plistlib 两种格式都认）。"""
    try:
        with zipfile.ZipFile(ipa) as archive:
            names = [name for name in archive.namelist()
                     if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", name)]
            if len(names) != 1:
                raise ReleaseError("安装包里应当正好有一个 Payload/*.app/Info.plist，实际有 {} 个".format(len(names)))
            info = plistlib.loads(archive.read(names[0]))
    except ReleaseError:
        raise
    except Exception as error:  # 压缩包或者 plist 坏了
        raise ReleaseError("读不出安装包里的 Info.plist：{}".format(error)) from None
    if not isinstance(info, dict):
        raise ReleaseError("安装包里的 Info.plist 不是字典")
    return info


def checksum(path: Path) -> tuple[str, int]:
    digest = hashlib.sha256()
    size = 0
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
            size += len(block)
    return digest.hexdigest(), size


# ---------------------------------------------------------------------------
# 仓库里的信息
# ---------------------------------------------------------------------------

def repository_url() -> str:
    repository = os.environ.get("GITHUB_REPOSITORY", "")
    if repository:
        return "{}/{}".format(os.environ.get("GITHUB_SERVER_URL", "https://github.com").rstrip("/"), repository)
    # 不在云端（本机试跑）：从远端地址推出来。地址里万一带着凭据，去掉。
    remote = re.sub(r"\.git$", "", git("remote", "get-url", "origin").strip())
    ssh = re.fullmatch(r"git@([^:]+):(.+)", remote)
    if ssh:
        return "https://{}/{}".format(ssh.group(1), ssh.group(2))
    return re.sub(r"^(https?://)[^/@]+@", r"\1", remote)


def release_tags(*extra: str) -> dict[str, int]:
    """本脚本发出来的那些标签，以及各自的构建号。"""
    tags: dict[str, int] = {}
    for line in git("tag", "--list", "v*", *extra).splitlines():
        name = line.strip()
        match = TAG_PATTERN.fullmatch(name)
        if match:
            tags[name] = int(match.group(1))
    return tags


def commits_since(previous: str) -> list[tuple[str, str]]:
    """从上一个发行版到现在的提交，新的在前。每一项是（完整的提交号，提交说明的第一行）。"""
    output = git("log", "--no-merges", "--format=%H%x09%s", "refs/tags/{}..HEAD".format(previous))
    commits = []
    for line in output.splitlines():
        sha, _, subject = line.partition("\t")
        if sha:
            commits.append((sha, subject.strip()))
    return commits


def upstreams() -> list[dict[str, str]]:
    """三个上游：名字、仓库地址、固定的版本、子模块指着的提交。不需要把子模块检出来。"""
    versions = json.loads((ROOT / "upstream" / "versions.json").read_text(encoding="utf-8"))
    config = git("config", "--file", ".gitmodules", "--get-regexp", r"^submodule\..*\.(path|url)$")
    modules: dict[str, dict[str, str]] = {}
    for line in config.splitlines():
        key, _, value = line.partition(" ")
        name, _, field = key[len("submodule."):].rpartition(".")
        modules.setdefault(name, {})[field] = value.strip()

    result = []
    for module in modules.values():
        path, url = module.get("path"), module.get("url")
        if not path or not url:
            continue
        # 子模块在树里是一条「160000 commit <提交号> <路径>」。
        entry = git("ls-tree", "HEAD", "--", path).split()
        if len(entry) < 3 or entry[1] != "commit":
            continue
        name = path.rsplit("/", 1)[-1]
        result.append({
            "name": name,
            "url": re.sub(r"\.git$", "", url),
            "version": str(versions.get(name, "")),
            "commit": entry[2],
        })
    return result


# ---------------------------------------------------------------------------
# 发行说明
# ---------------------------------------------------------------------------

def escape_markdown(text: str) -> str:
    """提交说明、版本号这些是普通文字，不是 Markdown：把会被当成格式的字符转义掉。"""
    text = text.replace("&", "&amp;")
    text = re.sub(r"([\\`*_{}\[\]<>|~#])", r"\\\1", text)
    # 「@名字」在 GitHub 上会通知到那个账号。在 @ 后面垫一个零宽空格，让它只是文字。
    return text.replace("@", "@​")


def short(sha: str) -> str:
    return sha[:7]


def build_notes(*, repo: str, commit: str, version: str, build: str, info: dict, asset_name: str,
                digest: str, size: int, previous: str | None, commits: list[tuple[str, str]],
                modules: list[dict[str, str]]) -> str:
    lines = [
        "未签名的安装包，要自己签名之后才能安装。下载下面的 `{}`。".format(asset_name),
        "",
        "| 项目 | 值 |",
        "| --- | --- |",
        "| 版本 | {} ({}) |".format(version, build),
    ]
    minimum_os = info.get("MinimumOSVersion")
    if minimum_os:
        lines.append("| 最低系统 | iOS {} |".format(escape_markdown(str(minimum_os))))
    bundle_id = info.get("CFBundleIdentifier")
    if bundle_id:
        lines.append("| 包名 | {} |".format(escape_markdown(str(bundle_id))))
    lines += [
        "| 大小 | {:.1f} MB |".format(size / 1048576),
        "| SHA-256 | `{}` |".format(digest),
        "| 对应的提交 | [`{}`]({}/commit/{}) |".format(short(commit), repo, commit),
        "",
    ]

    run_id = os.environ.get("GITHUB_RUN_ID", "")
    tested = "这一版在云端编译通过，并在模拟器上跑过了界面测试"
    if run_id:
        tested += "（[构建记录]({}/actions/runs/{})）".format(repo, run_id)
    lines += [tested + "。界面测试不登录，登录之后的功能没有覆盖到。", ""]

    if modules:
        lines += ["### 里面的应用", "", "| 应用 | 上游版本 | 上游提交 |", "| --- | --- | --- |"]
        for module in modules:
            lines.append("| [{}]({}) | {} | [`{}`]({}/commit/{}) |".format(
                escape_markdown(module["name"]), module["url"], escape_markdown(module["version"]),
                short(module["commit"]), module["url"], module["commit"]))
        lines.append("")

    lines += ["### 这一版的改动", ""]
    if previous is None:
        lines.append("这是第一个发行版，之前的改动见[提交历史]({}/commits/{})。".format(repo, commit))
    elif not commits:
        lines.append("和上一个发行版 [{0}]({1}/releases/tag/{0}) 是同一份代码，只是重新构建了一次。".format(previous, repo))
    else:
        lines += ["自上一个发行版 [{0}]({1}/releases/tag/{0}) 以来的提交：".format(previous, repo), ""]
        for sha, subject in commits[:MAX_COMMITS]:
            lines.append("- {}（[`{}`]({}/commit/{})）".format(escape_markdown(subject), short(sha), repo, sha))
        if len(commits) > MAX_COMMITS:
            lines.append("- ……以及更早的 {} 个提交，见[完整的对比]({}/compare/{}...{})".format(
                len(commits) - MAX_COMMITS, repo, previous, commit))
    lines.append("")

    lines += [
        "### 源码和许可证",
        "",
        "整合后的整体按 [GNU AGPL-3.0]({0}/blob/{1}/LICENSE) 发布，上游项目的版权和许可信息见 "
        "[NOTICE.md]({0}/blob/{1}/NOTICE.md)。".format(repo, commit),
        "",
        "这个安装包对应的源码，是本仓库在上面那个提交处的内容，加上表里几个上游在各自提交处的内容；"
        "本仓库对上游的全部改动在 `patches/`、`bridges/` 和 `scripts/prepare.py` 里。"
        "下面自动附带的 Source code 压缩包只有本仓库自己的文件，不含 `upstream/` 下几个上游的源码。",
        "",
    ]
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# 发布
# ---------------------------------------------------------------------------

def release_exists(tag: str) -> bool:
    try:
        result = subprocess.run(["gh", "release", "view", tag, "--json", "tagName"], cwd=ROOT, capture_output=True)
    except FileNotFoundError:
        raise ReleaseError("找不到 gh 命令") from None
    return result.returncode == 0


def verify(tag: str, asset_name: str, size: int) -> tuple[list[str], list[str]]:
    """发完之后回头看一眼：发行版是不是已经公开、安装包在不在、大小对不对。

    返回（确实有问题的地方，没能核对的地方）。前者算发布失败，后者只提醒。
    """
    try:
        data = json.loads(gh("release", "view", tag, "--json", "isDraft,assets"))
    except (ReleaseError, ValueError) as error:
        return [], ["没能读回发行版 {} 的信息：{}".format(tag, error)]
    if not isinstance(data, dict):
        return [], ["读回的发行版信息不是预期的格式"]

    problems = []
    if data.get("isDraft"):
        problems.append("发行版 {} 还是草稿，别人看不到".format(tag))
    assets = [asset for asset in (data.get("assets") or []) if isinstance(asset, dict)]
    matching = [asset for asset in assets if asset.get("name") == asset_name]
    if not matching:
        problems.append("发行版 {} 里没有 {}，里面现有：{}".format(
            tag, asset_name, "、".join(str(asset.get("name")) for asset in assets) or "（空的）"))
    elif matching[0].get("size") != size:
        problems.append("发行版里的 {} 是 {} 字节，本地的是 {} 字节".format(asset_name, matching[0].get("size"), size))
    return problems, []


def publish(argument: str, dry_run: bool) -> int:
    ipa = locate_ipa(argument)
    info = read_bundle_info(ipa)

    version = str(info.get("CFBundleShortVersionString", ""))
    build = str(info.get("CFBundleVersion", ""))
    if not VERSION_PATTERN.fullmatch(version) or not BUILD_PATTERN.fullmatch(build):
        raise ReleaseError("安装包里的版本号「{}」或构建号「{}」不是预期的格式（只能是数字和点）".format(version, build))

    # 构建号默认就是这次运行的序号。对不上说明版本没有写进安装包，照这样发下去每次都是同一个标签。
    run_number = os.environ.get("GITHUB_RUN_NUMBER", "")
    if run_number and not os.environ.get("HUB_BUILD_NUMBER") and build != run_number:
        raise ReleaseError("安装包里的构建号是 {}，这次运行的序号是 {}，两者应当相同".format(build, run_number))

    tag = "v{}-{}".format(version, build)
    title = "Hub {} ({})".format(version, build)
    build_number = int(build)
    commit = git("rev-parse", "HEAD").strip()
    repo = repository_url()

    all_tags = release_tags()
    if tag in all_tags:
        tagged = git("rev-parse", "refs/tags/{}^{{commit}}".format(tag)).strip()
        if tagged != commit:
            raise ReleaseError("标签 {} 已经有了，而且指向另一个提交 {}（现在是 {}）。不覆盖已经发出去的版本".format(
                tag, short(tagged), short(commit)))

    # 上一个发行版：历史上在这个提交之前、构建号比这次小的那些里最新的一个。
    earlier = {name: number for name, number in release_tags("--merged", "HEAD").items() if number < build_number}
    previous = max(earlier, key=earlier.__getitem__) if earlier else None
    # 重跑一次旧的构建时，不能把「最新」从更新的发行版手里抢回来。
    latest = all(number <= build_number for number in all_tags.values())

    digest, size = checksum(ipa)
    notes = build_notes(
        repo=repo, commit=commit, version=version, build=build, info=info, asset_name=ipa.name,
        digest=digest, size=size, previous=previous,
        commits=commits_since(previous) if previous else [],
        modules=upstreams(),
    )

    print("标签：{}".format(tag))
    print("标题：{}".format(title))
    print("标为最新：{}".format("是" if latest else "否"))
    print("上一个发行版：{}".format(previous or "没有，这是第一个"))
    print("安装包：{}（{:.1f} MB，SHA-256 {}）".format(ipa, size / 1048576, digest))
    print("===== 发行说明 =====")
    print(notes)

    if dry_run:
        print("===== 试跑结束，没有创建任何东西 =====")
        return 0

    OUTPUT.mkdir(parents=True, exist_ok=True)
    notes_path = OUTPUT / "notes.md"
    notes_path.write_text(notes, encoding="utf-8")

    latest_flag = "--latest" if latest else "--latest=false"
    if release_exists(tag):
        print("发行版 {} 已经有了（重跑同一次构建），替换里面的安装包".format(tag))
        gh("release", "upload", tag, str(ipa), "--clobber")
        gh("release", "edit", tag, "--title", title, "--notes-file", str(notes_path), "--draft=false", latest_flag)
    else:
        print(gh("release", "create", tag, str(ipa), "--target", commit, "--title", title,
                 "--notes-file", str(notes_path), latest_flag))

    problems, unchecked = verify(tag, ipa.name, size)
    if problems:
        raise ReleaseError("发布之后核对出了问题：\n" + "\n".join(problems))
    if unchecked:
        annotate("warning", "发布之后没能核对", unchecked)

    page = "{}/releases/tag/{}".format(repo, tag)
    summary = [
        "标签 {}（标为最新：{}）".format(tag, "是" if latest else "否"),
        "安装包 {}，{:.1f} MB（{} 字节）".format(ipa.name, size / 1048576, size),
        "SHA-256：{}".format(digest),
        "发行版页面：{}".format(page),
        "这一版的下载地址：{}/releases/download/{}/{}".format(repo, tag, ipa.name),
    ]
    if latest:
        summary.append("最新一版的固定下载地址：{}/releases/latest/download/{}".format(repo, ipa.name))
    annotate("notice", "已发布", summary)

    step_summary = os.environ.get("GITHUB_STEP_SUMMARY", "")
    if step_summary:
        with open(step_summary, "a", encoding="utf-8") as handle:
            handle.write("### 已发布 [{}]({})\n\n".format(tag, page))
            handle.write("".join("- {}\n".format(line) for line in summary[1:]))
    return 0


def main() -> int:
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8")
    arguments = [argument for argument in sys.argv[1:] if argument != "--dry-run"]
    dry_run = "--dry-run" in sys.argv[1:]
    if len(arguments) != 1:
        print("用法：publish_release.py <Hub.ipa，或者放着它的目录> [--dry-run]", file=sys.stderr)
        return 2
    try:
        return publish(arguments[0], dry_run)
    except ReleaseError as error:
        print("发布失败：{}".format(error))
        if not dry_run:
            annotate("error", "发布失败", str(error).splitlines())
        return 1


if __name__ == "__main__":
    sys.exit(main())

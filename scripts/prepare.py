#!/usr/bin/env python3
"""构建前的准备脚本。

上游仓库以 git 子模块的形式保持原样，所有对上游的改动都集中在这个脚本里：

1. patch    给上游源码打补丁（定位文字必须恰好出现一次，否则报错，提醒人工核对）
2. bridges  把 bridges/ 下的桥接文件复制进上游模块目录（只新增文件，不改上游文件）
3. tags     准备 Pixiv 的标签翻译数据 generated/tags.json
4. resolved 合并两个上游的依赖锁定文件，写进生成的 Xcode 工程

用法见 `python3 scripts/prepare.py --help`。只依赖标准库，兼容 Python 3.9 及以上。
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import re
import subprocess
import sys
import urllib.request
import zipfile
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UPSTREAM = ROOT / "upstream"
EHPANDA = UPSTREAM / "EhPanda"
PIXIV = UPSTREAM / "Pixiv-SwiftUI"
BRIDGES = ROOT / "bridges"
GENERATED = ROOT / "generated"
VERSIONS_FILE = UPSTREAM / "versions.json"

# 桥接文件的去向：bridges/<名字>/ 下的目录结构原样复制到对应的上游目录。
BRIDGE_DESTINATIONS = {
    "ehpanda": EHPANDA / "AppPackage" / "Sources",
}

# 宿主的 Pixiv 入口视图（App/Modules/PixivRootView.swift）是照着上游这个文件写的。
# 上游改了它，这里的校验和就对不上，脚本会给出提醒，届时需要人工核对入口视图。
PIXIV_ENTRY_FILE = "Pixiv-SwiftUI/App/PixivApp.swift"
PIXIV_ENTRY_SHA256 = "2da13b2bfc99e271ae493c040d2ece5c21ecb1f023712c84aa9f2a68f7c8e24b"

# 合并依赖锁定文件时丢弃的包（对应的依赖已被补丁移除）。
SKIPPED_PIN_IDENTITIES = {"swiftlintplugins"}

EMPTY_TAGS = {"timestamp": "1970-01-01T00:00:00", "tags": {}}


class PrepareError(Exception):
    """准备过程中需要人工处理的问题。"""


@dataclass(frozen=True)
class Patch:
    repo: Path
    path: str
    title: str
    find: str
    replace: str
    # 打完补丁后文件里一定会出现的文字，用来判断是否已经打过。
    marker: str
    # find 是否按正则表达式处理（用于版本号之类会随上游变化的内容）。
    regex: bool = False

    @property
    def target(self) -> Path:
        return self.repo / self.path


PATCHES = [
    Patch(
        repo=EHPANDA,
        path="AppPackage/Package.swift",
        title="移除 SwiftLintPlugins 依赖",
        find=r'^[ \t]*\.package\(url: "https://github\.com/SimplyDanny/SwiftLintPlugins"[^\n]*\n',
        replace="    // [Hub] 已移除 SwiftLintPlugins 依赖：下游构建不运行上游的代码规范检查。\n",
        marker="[Hub] 已移除 SwiftLintPlugins 依赖",
        regex=True,
    ),
    Patch(
        repo=EHPANDA,
        path="AppPackage/Package.swift",
        title="清空 SwiftLint 构建插件列表",
        find=r"^let swiftLintPlugins: \[PackageDescription\.Target\.PluginUsage\] = \[\n[^\]]*\]\n",
        replace=(
            "// [Hub] 已清空 SwiftLint 构建插件列表，原因同上。\n"
            "let swiftLintPlugins: [PackageDescription.Target.PluginUsage] = []\n"
        ),
        marker="[Hub] 已清空 SwiftLint 构建插件列表",
        regex=True,
    ),
    Patch(
        repo=EHPANDA,
        path="AppPackage/Sources/NetworkingFeature/DFURLProtocol.swift",
        title="域名前置只接管 E-Hentai 系站点",
        find=r'''            logger.error("URL scheme \"\(scheme, privacy: .public)\" is not supported.")
            return false
        }
        return true
    }
''',
        replace=r'''            logger.error("URL scheme \"\(scheme, privacy: .public)\" is not supported.")
            return false
        }
        // [Hub] 合并进同一个 App 后，域名前置只接管 E-Hentai 系站点，
        // 其余请求（例如 Pixiv 的接口和图片）交还系统默认通道。
        return hubShouldFront(request)
    }

    private static let hubFrontedDomainSuffixes = ["e-hentai.org", "exhentai.org", "ehgt.org", "hath.network"]

    private static func hubShouldFront(_ request: URLRequest) -> Bool {
        guard let domain = request.domain?.lowercased(), !domain.isEmpty else { return false }
        if ResolvableDomain(rawValue: domain) != nil { return true }
        return hubFrontedDomainSuffixes.contains { domain == $0 || domain.hasSuffix("." + $0) }
    }
''',
        marker="[Hub] 合并进同一个 App 后，域名前置只接管 E-Hentai 系站点",
    ),
    Patch(
        repo=PIXIV,
        path=PIXIV_ENTRY_FILE,
        title="去掉 Pixiv 的 @main 入口",
        find="@main\nstruct PixivApp: App {\n",
        replace=(
            "// [Hub] 已去掉 @main：程序入口由宿主 App 接管，本文件其余内容保持原样。\n"
            "struct PixivApp: App {\n"
        ),
        marker="[Hub] 已去掉 @main",
    ),
    Patch(
        repo=PIXIV,
        path="Pixiv-SwiftUI/Core/Network/CustomProxyConfiguration.swift",
        title="Pixiv 调整图片代理时保留下载器的现有配置",
        find='''        let configuration = URLSessionConfiguration.ephemeral
        apply(proxy, to: configuration)
        return configuration
''',
        replace='''        // [Hub] 与 EhPanda 共用 Kingfisher 默认下载器：在现有配置上只调整代理，
        // 保留对方设置的 Cookie 存储和协议类，避免互相覆盖。
        let configuration = ImageDownloader.default.sessionConfiguration
        configuration.proxyConfigurations = []
        apply(proxy, to: configuration)
        return configuration
''',
        marker="[Hub] 与 EhPanda 共用 Kingfisher 默认下载器",
    ),
]


# ---------------------------------------------------------------------------
# 通用工具
# ---------------------------------------------------------------------------

def say(message: str) -> None:
    print(message, flush=True)


def warn(message: str) -> None:
    if os.environ.get("GITHUB_ACTIONS") == "true":
        print("::warning::" + message.replace("\n", " "), flush=True)
    else:
        print("警告：" + message, flush=True)


def read_text(path: Path) -> tuple[str, str]:
    """读取文本，统一成 LF 换行返回，同时返回文件原本的换行符。"""
    raw = path.read_bytes().decode("utf-8")
    newline = "\r\n" if "\r\n" in raw else "\n"
    return raw.replace("\r\n", "\n"), newline


def write_text(path: Path, text: str, newline: str) -> None:
    path.write_bytes(text.replace("\n", newline).encode("utf-8"))


def relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def require_upstream() -> None:
    for repo in (EHPANDA, PIXIV):
        if not any(repo.glob("*")):
            raise PrepareError(
                "上游目录 {} 是空的，请先执行 git submodule update --init --recursive".format(relative(repo))
            )


# ---------------------------------------------------------------------------
# 补丁
# ---------------------------------------------------------------------------

def patched_text(patch: Patch, text: str) -> str:
    if patch.regex:
        new_text, count = re.subn(patch.find, lambda _match: patch.replace, text, flags=re.MULTILINE)
    else:
        count = text.count(patch.find)
        new_text = text.replace(patch.find, patch.replace)
    if count != 1:
        raise PrepareError(
            "补丁「{}」的定位文字在 {} 里出现了 {} 次（应当恰好 1 次）。"
            "上游很可能改了这段代码，需要人工核对后更新 scripts/prepare.py 里的补丁。".format(
                patch.title, relative(patch.target), count
            )
        )
    if patch.marker not in new_text:
        raise PrepareError("补丁「{}」写得有问题：替换后的内容里没有它自己的标记。".format(patch.title))
    return new_text


def apply_patches(dry_run: bool) -> None:
    say("== 上游补丁 ==")
    for patch in PATCHES:
        if not patch.target.is_file():
            raise PrepareError("找不到要打补丁的文件：{}".format(relative(patch.target)))
        text, newline = read_text(patch.target)
        if patch.marker in text:
            say("  已打过  {}".format(patch.title))
            continue
        new_text = patched_text(patch, text)
        if dry_run:
            say("  可应用  {}".format(patch.title))
        else:
            write_text(patch.target, new_text, newline)
            say("  已应用  {}".format(patch.title))


def check_pixiv_entry() -> None:
    """上游的入口文件一旦变化就提醒：宿主的 Pixiv 入口视图是照着它写的。"""
    target = PIXIV / PIXIV_ENTRY_FILE
    text, _newline = read_text(target)
    for patch in PATCHES:
        if patch.target == target and not patch.regex:
            text = text.replace(patch.replace, patch.find)
    digest = hashlib.sha256(text.encode("utf-8")).hexdigest()
    if digest == PIXIV_ENTRY_SHA256:
        say("  入口文件与记录一致  {}".format(PIXIV_ENTRY_FILE))
    else:
        warn(
            "Pixiv 上游的入口文件 {} 有变化（当前校验和 {}）。请对照它核对 App/Modules/PixivRootView.swift，"
            "确认无误后把 scripts/prepare.py 里的 PIXIV_ENTRY_SHA256 更新为这个值。".format(PIXIV_ENTRY_FILE, digest)
        )


# ---------------------------------------------------------------------------
# 桥接文件
# ---------------------------------------------------------------------------

def bridge_pairs() -> list[tuple[Path, Path]]:
    pairs = []
    for name, destination_root in sorted(BRIDGE_DESTINATIONS.items()):
        source_root = BRIDGES / name
        if not source_root.is_dir():
            continue
        for source in sorted(path for path in source_root.rglob("*") if path.is_file()):
            pairs.append((source, destination_root / source.relative_to(source_root)))
    return pairs


def inject_bridges(dry_run: bool) -> None:
    say("== 桥接文件 ==")
    for source, destination in bridge_pairs():
        if not destination.parent.is_dir():
            raise PrepareError(
                "桥接文件 {} 要放进的目录 {} 不存在，上游可能调整了模块结构。".format(
                    relative(source), relative(destination.parent)
                )
            )
        if dry_run:
            say("  可复制  {}".format(relative(destination)))
            continue
        destination.write_bytes(source.read_bytes())
        say("  已复制  {}".format(relative(destination)))


# ---------------------------------------------------------------------------
# 标签翻译数据
# ---------------------------------------------------------------------------

def pinned_versions() -> dict:
    if not VERSIONS_FILE.is_file():
        raise PrepareError("缺少 {}".format(relative(VERSIONS_FILE)))
    return json.loads(VERSIONS_FILE.read_text(encoding="utf-8"))


def tags_from_release(tag: str) -> dict:
    url = "https://github.com/Eslzzyl/Pixiv-SwiftUI/releases/download/{}/Pixiv-SwiftUI.ipa".format(tag)
    request = urllib.request.Request(url, headers={"User-Agent": "hub-prepare-script"})
    with urllib.request.urlopen(request, timeout=180) as response:
        payload = response.read()
    with zipfile.ZipFile(io.BytesIO(payload)) as archive:
        members = [
            name for name in archive.namelist()
            if re.fullmatch(r"Payload/[^/]+\.app/tags\.json", name)
        ]
        if len(members) != 1:
            raise PrepareError("发行包里没有找到唯一的 tags.json（找到 {} 个）。".format(len(members)))
        data = json.loads(archive.read(members[0]).decode("utf-8"))
    if not isinstance(data, dict) or not isinstance(data.get("tags"), dict) or not data["tags"]:
        raise PrepareError("发行包里的 tags.json 结构不符合预期。")
    if not isinstance(data.get("timestamp"), str):
        raise PrepareError("发行包里的 tags.json 缺少 timestamp。")
    return data


def prepare_tags(mode: str) -> None:
    say("== Pixiv 标签翻译数据 ==")
    output = GENERATED / "tags.json"
    GENERATED.mkdir(exist_ok=True)
    data = None
    if mode in ("auto", "release"):
        tag = pinned_versions()["Pixiv-SwiftUI"]
        try:
            data = tags_from_release(tag)
            say("  取自上游 {} 发行包，共 {} 条".format(tag, len(data["tags"])))
        except Exception as error:  # 网络问题、发行包结构变化等
            if mode == "release":
                raise PrepareError("从上游 {} 发行包提取标签数据失败：{}".format(tag, error))
            warn("从上游 {} 发行包提取标签数据失败（{}），改用空数据，标签翻译将回退到 Pixiv 自带的译名。".format(tag, error))
    if data is None:
        data = EMPTY_TAGS
        say("  使用空的标签数据")
    output.write_text(json.dumps(data, ensure_ascii=False, sort_keys=True, separators=(",", ":")), encoding="utf-8")
    say("  已写入  {}".format(relative(output)))


# ---------------------------------------------------------------------------
# 依赖锁定文件
# ---------------------------------------------------------------------------

def pin_version_key(pin: dict) -> tuple:
    """把锁定条目的版本号变成可比较的元组；没有版本号（按分支或提交锁定）的排在最前。"""
    version = pin.get("state", {}).get("version") or ""
    return tuple(int(piece) if piece.isdigit() else -1 for piece in re.split(r"[.+-]", version))


def merge_resolved(project: Path) -> None:
    say("== 依赖锁定文件 ==")
    sources = [
        EHPANDA / "AppPackage" / "Package.resolved",
        PIXIV / "Pixiv-SwiftUI.xcodeproj" / "project.xcworkspace" / "xcshareddata" / "swiftpm" / "Package.resolved",
    ]
    pins = {}
    for source in sources:
        data = json.loads(source.read_text(encoding="utf-8"))
        for pin in data.get("pins", []):
            identity = pin["identity"]
            if identity in SKIPPED_PIN_IDENTITIES:
                continue
            if identity in pins:
                # 两边都依赖的包取较高的版本：它同时落在两边声明的版本范围里，
                # 而锁定较低版本的一方按语义化版本应当兼容；反过来，较高的一方可能用到了新接口。
                if pin_version_key(pin) > pin_version_key(pins[identity]):
                    pins[identity] = pin
                continue
            pins[identity] = pin
    if not project.is_dir():
        raise PrepareError("找不到 Xcode 工程 {}，请先运行 xcodegen generate".format(project))
    destination = project / "project.xcworkspace" / "xcshareddata" / "swiftpm" / "Package.resolved"
    destination.parent.mkdir(parents=True, exist_ok=True)
    merged = {"pins": [pins[identity] for identity in sorted(pins)], "version": 3}
    destination.write_text(json.dumps(merged, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    say("  已写入 {} 个包的锁定版本".format(len(pins)))


# ---------------------------------------------------------------------------
# 还原
# ---------------------------------------------------------------------------

def revert() -> None:
    """把上游子模块恢复成没打补丁、没注入文件的原样（本机调试用）。"""
    say("== 还原上游 ==")
    for patch in PATCHES:
        subprocess.run(["git", "-C", str(patch.repo), "checkout", "--", patch.path], check=True)
        say("  已还原  {}".format(relative(patch.target)))
    for _source, destination in bridge_pairs():
        if destination.is_file():
            destination.unlink()
            say("  已删除  {}".format(relative(destination)))


# ---------------------------------------------------------------------------
# 入口
# ---------------------------------------------------------------------------

def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")

    parser = argparse.ArgumentParser(description="构建前准备：给上游打补丁、注入桥接文件、准备数据。")
    commands = parser.add_subparsers(dest="command", required=True)

    all_parser = commands.add_parser("all", help="依次执行 patch、bridges、tags")
    all_parser.add_argument("--tags", choices=["auto", "release", "empty"], default="auto")
    all_parser.add_argument("--dry-run", action="store_true", help="只检查，不改动任何文件")

    patch_parser = commands.add_parser("patch", help="只打补丁并注入桥接文件")
    patch_parser.add_argument("--dry-run", action="store_true", help="只检查，不改动任何文件")

    tags_parser = commands.add_parser("tags", help="只准备标签翻译数据")
    tags_parser.add_argument("--mode", choices=["auto", "release", "empty"], default="auto")

    resolved_parser = commands.add_parser("resolved", help="把合并后的依赖锁定文件写进 Xcode 工程")
    resolved_parser.add_argument("--project", required=True, help="xcodegen 生成的 .xcodeproj 路径")

    commands.add_parser("revert", help="把上游子模块恢复原样")

    arguments = parser.parse_args()
    try:
        require_upstream()
        if arguments.command in ("all", "patch"):
            apply_patches(arguments.dry_run)
            check_pixiv_entry()
            inject_bridges(arguments.dry_run)
        if arguments.command == "all" and not arguments.dry_run:
            prepare_tags(arguments.tags)
        if arguments.command == "tags":
            prepare_tags(arguments.mode)
        if arguments.command == "resolved":
            merge_resolved(Path(arguments.project).resolve())
        if arguments.command == "revert":
            revert()
    except PrepareError as error:
        if os.environ.get("GITHUB_ACTIONS") == "true":
            print("::error::" + str(error).replace("\n", " "), flush=True)
        print("出错：" + str(error), file=sys.stderr, flush=True)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

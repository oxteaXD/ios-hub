#!/bin/bash
# 编译宿主 App 并打包成未签名的 IPA。在 macOS 上运行。
#
# 运行前需要先完成：
#   python3 scripts/prepare.py all
#   xcodegen generate
#   python3 scripts/prepare.py resolved --project Hub.xcodeproj
#
# 可用的环境变量：
#   HUB_VERSION       版本号，默认取当天日期（如 2026.11.14）
#   HUB_BUILD_NUMBER  构建号，默认取 GitHub Actions 的运行序号，本地为 1
set -euo pipefail

cd "$(dirname "$0")/.."

SCHEME="Hub"
PROJECT="Hub.xcodeproj"
DERIVED_DATA="build/DerivedData"
LOG="build/xcodebuild.log"
ERRORS="build/errors.txt"
APP="build/Payload/${SCHEME}.app"
IPA="build/${SCHEME}.ipa"

# 版本号的每一段都不能带前导零，所以月和日转成十进制整数。
DEFAULT_VERSION="$(date -u +%Y).$((10#$(date -u +%m))).$((10#$(date -u +%d)))"
VERSION="${HUB_VERSION:-$DEFAULT_VERSION}"
BUILD_NUMBER="${HUB_BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-1}}"

if [ ! -d "$PROJECT" ]; then
    echo "找不到 ${PROJECT}，请先运行 xcodegen generate"
    exit 1
fi

mkdir -p build
echo "开始编译 ${SCHEME} ${VERSION} (${BUILD_NUMBER})，完整日志写入 ${LOG}"

set +e
xcodebuild build \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -sdk iphoneos \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$DERIVED_DATA" \
    -skipMacroValidation \
    -skipPackagePluginValidation \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    > "$LOG" 2>&1
STATUS=$?
set -e

if [ "$STATUS" -ne 0 ]; then
    echo "编译失败，xcodebuild 退出码 ${STATUS}"

    # 把报错行挑出来去重，方便直接在运行页面上看，不用翻完整日志。
    grep -E "(error:|fatal error|\*\* BUILD FAILED \*\*)" "$LOG" \
        | sed -e 's/^[[:space:]]*//' \
        | awk '!seen[$0]++' \
        | head -n 200 > "$ERRORS" || true

    echo "===== 报错摘要 ====="
    cat "$ERRORS"
    echo "===== 日志末尾 ====="
    tail -n 40 "$LOG"

    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
        {
            echo "### 编译失败"
            echo
            echo '```'
            cat "$ERRORS"
            echo '```'
        } >> "$GITHUB_STEP_SUMMARY"
    fi
    if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
        head -n 10 "$ERRORS" | while IFS= read -r line; do
            echo "::error::${line}"
        done
    fi
    exit "$STATUS"
fi

echo "编译完成，开始打包"

BUILT_APP="${DERIVED_DATA}/Build/Products/Release-iphoneos/${SCHEME}.app"
if [ ! -d "$BUILT_APP" ]; then
    echo "找不到构建产物 ${BUILT_APP}，现有的产物目录："
    find "${DERIVED_DATA}/Build/Products" -maxdepth 2 -type d 2>/dev/null || true
    exit 1
fi

rm -rf build/Payload "$IPA"
mkdir -p build/Payload
cp -R "$BUILT_APP" build/Payload/

# 可执行文件和 Info.plist 缺了就不是一个能装的包，直接判失败。
for item in "$SCHEME" Info.plist; do
    if [ ! -e "${APP}/${item}" ]; then
        echo "构建产物里缺少 ${item}，包内的文件如下："
        ls "$APP"
        exit 1
    fi
done

# 下面几样缺了，对应的功能在设备上会是坏的（图片、标签翻译、中文文案、EhPanda 的资源）。
# 它们的文件名取决于 Xcode 的打包方式，所以只给出警告并列出包内文件，由人来判断。
MISSING=""
for item in Assets.car tags.json zh-Hans.lproj AppPackage_AppFeature.bundle; do
    if [ -e "${APP}/${item}" ]; then
        echo "  包内有 ${item}"
    else
        echo "  包内没有找到 ${item}"
        MISSING="${MISSING} ${item}"
    fi
done
if [ -n "$MISSING" ]; then
    if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
        echo "::warning::构建产物里没有找到：${MISSING}"
    fi
    echo "包内的文件如下："
    ls "$APP"
fi

# Pica 的代码和它的依赖库是按需载入的动态框架。两件事要保证：它们都在安装包里；主程序没有直接链接它们。
# 链接了的话它们会随 App 启动一起载入，QMUIKit 对系统界面方法的改写就会波及另外两个应用。
PICA_FRAMEWORKS="PicaKit AFNetworking FMDB GYDataCenter JXPagingView MJRefresh QMUIKit SDWebImage SDWebImageVideoCoder SSZipArchive SocketRocket YTKNetwork YYModel"
for name in $PICA_FRAMEWORKS; do
    if [ ! -f "${APP}/Frameworks/${name}.framework/${name}" ]; then
        echo "构建产物里缺少 Frameworks/${name}.framework，Pica 会打不开。Frameworks 目录里现有："
        ls "${APP}/Frameworks" 2>/dev/null || echo "（没有 Frameworks 目录）"
        exit 1
    fi
done
# 主程序启动时就要载入的内嵌框架（install name 以 @rpath/ 开头的那些）。
LINKED_AT_LAUNCH="$(xcrun otool -L "${APP}/${SCHEME}" | awk '$1 ~ /^@rpath\// {print $1}' | sed -e 's#^@rpath/##' | tr '\n' ' ')"
for name in $PICA_FRAMEWORKS; do
    case " ${LINKED_AT_LAUNCH}" in
        *"/${name} "*)
            echo "主程序直接链接了 ${name}：它会随 App 启动一起载入，而不是进入 Pica 时才载入"
            exit 1
            ;;
    esac
done
echo "  Pica 的 13 个框架都在安装包里，主程序没有直接链接它们"

(cd build && zip -qry "${SCHEME}.ipa" Payload)

SIZE_MB="$(du -m "$IPA" | cut -f1)"
MIN_OS="$(/usr/bin/plutil -extract MinimumOSVersion raw -o - "${APP}/Info.plist")"
BUNDLE_ID="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "${APP}/Info.plist")"

echo "打包完成：${IPA}（${SIZE_MB} MB，最低系统 ${MIN_OS}，包名 ${BUNDLE_ID}）"

# 命名颜色编译在 Assets.car 里，从文件清单上看不出来，用 assetutil 列出来。
# assetutil 输出的是 JSON（名字里的斜杠会转义成 \/），所以交给 JSON 解析，不用文本匹配。
ASSET_INFO="build/assets-info.json"
xcrun assetutil --info "${APP}/Assets.car" > "$ASSET_INFO" 2>/dev/null || true
COLOR_NAMES="$(python3 -I - "$ASSET_INFO" <<'PY' || true
import json, sys

try:
    entries = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    entries = []
names = {e.get("Name", "") for e in entries if isinstance(e, dict) and e.get("AssetType") == "Color"}
print("\n".join(sorted(name for name in names if name)))
PY
)"

# EhPanda 的分类颜色，上游一共 22 个（E-Hentai 和 ExHentai 各 11 个分类）；
# 少了的话列表里的分类标签会没有底色。
CATEGORY_COLORS="$(printf '%s\n' "$COLOR_NAMES" | grep -cE '^(E-Hentai|ExHentai)/' || true)"
CATEGORY_COLORS="${CATEGORY_COLORS:-0}"
echo "  资源目录里的 EhPanda 分类颜色：${CATEGORY_COLORS} 个"
if [ "$CATEGORY_COLORS" -ne 22 ] && [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    echo "::warning::资源目录里的 EhPanda 分类颜色是 ${CATEGORY_COLORS} 个，应为 22 个"
fi

# 实际参与编译的资源目录，从编译日志里找。
CATALOGS="$(grep -oE '[^ /"]+\.xcassets' "$LOG" | sort -u | tr '\n' ' ' || true)"

# 包内容清单：不下载安装包也能核对里面有什么。
CONTENTS="build/contents.txt"
{
    echo "可执行文件：$(du -h "${APP}/${SCHEME}" | cut -f1)"
    echo "参与编译的资源目录：${CATALOGS}"
    echo "EhPanda 分类颜色：${CATEGORY_COLORS} 个（应为 22 个）"
    echo "资源目录里的全部命名颜色："
    printf '%s\n' "$COLOR_NAMES" | sed -e 's/^/    /'
    echo "资源包（.bundle）：$(find "$APP" -maxdepth 1 -name '*.bundle' | wc -l | tr -d ' ') 个"
    echo "语言目录（.lproj）：$(find "$APP" -maxdepth 1 -name '*.lproj' -exec basename {} .lproj \; | sort | tr '\n' ' ')"
    echo "内嵌框架：$(find "${APP}/Frameworks" -maxdepth 1 -mindepth 1 2>/dev/null | wc -l | tr -d ' ') 个（$(find "${APP}/Frameworks" -maxdepth 1 -mindepth 1 -exec basename {} .framework \; 2>/dev/null | sort | tr '\n' ' ')）"
    echo "其中主程序启动时就载入的：${LINKED_AT_LAUNCH:-没有}（Pica 的框架应当都不在这里，它们进入 Pica 时才载入）"
    echo
    echo "顶层文件："
    ls -1 "$APP"
    echo
    echo "Info.plist："
    /usr/bin/plutil -p "${APP}/Info.plist"
} > "$CONTENTS"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
        echo "### 构建成功"
        echo
        echo "| 项目 | 值 |"
        echo "| --- | --- |"
        echo "| 版本 | ${VERSION} (${BUILD_NUMBER}) |"
        echo "| 大小 | ${SIZE_MB} MB |"
        echo "| 最低系统 | iOS ${MIN_OS} |"
        echo "| 包名 | ${BUNDLE_ID} |"
        echo
        echo "<details><summary>包内容清单</summary>"
        echo
        echo '```'
        cat "$CONTENTS"
        echo '```'
        echo
        echo "</details>"
    } >> "$GITHUB_STEP_SUMMARY"
fi

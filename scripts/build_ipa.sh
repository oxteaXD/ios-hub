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

(cd build && zip -qry "${SCHEME}.ipa" Payload)

SIZE_MB="$(du -m "$IPA" | cut -f1)"
MIN_OS="$(/usr/bin/plutil -extract MinimumOSVersion raw -o - "${APP}/Info.plist")"
BUNDLE_ID="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "${APP}/Info.plist")"

echo "打包完成：${IPA}（${SIZE_MB} MB，最低系统 ${MIN_OS}，包名 ${BUNDLE_ID}）"

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
    } >> "$GITHUB_STEP_SUMMARY"
fi

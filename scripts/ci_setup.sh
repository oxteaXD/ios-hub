#!/bin/bash
# 云端构建里各个作业共用的准备步骤：安装 XcodeGen、确认 iOS 平台、准备上游源码、生成 Xcode 工程。
# 在 macOS 上运行；在自己的 Mac 上想从头生成工程也可以直接用它。
set -euo pipefail

cd "$(dirname "$0")/.."

echo "===== 工具链版本 ====="
xcodebuild -version
swift --version 2>&1 | head -n 2
python3 --version

echo "===== 安装 XcodeGen ====="
if ! command -v xcodegen >/dev/null 2>&1; then
    if command -v brew >/dev/null 2>&1 && brew install xcodegen; then
        echo "已通过 Homebrew 安装"
    else
        # 没有 Homebrew 时，直接用官方发行包里的可执行文件。
        TOOLS="${RUNNER_TEMP:-/tmp}/xcodegen-dist"
        curl -fsSL -o "${TOOLS}.zip" https://github.com/yonaskolb/XcodeGen/releases/latest/download/xcodegen.zip
        rm -rf "$TOOLS"
        unzip -q "${TOOLS}.zip" -d "$TOOLS"
        export PATH="${TOOLS}/xcodegen/bin:${PATH}"
    fi
fi
xcodegen --version

echo "===== 确认 iOS 平台可用 ====="
if xcrun simctl list runtimes 2>/dev/null | grep -q "iOS"; then
    echo "iOS 平台已安装"
else
    # 编译资源目录需要 iOS 平台组件；镜像里没有预装时下载，网络不稳所以重试几次。
    for attempt in 1 2 3 4 5; do
        if xcodebuild -downloadPlatform iOS; then
            break
        fi
        echo "第 ${attempt} 次下载失败，20 秒后重试"
        sleep 20
    done
    xcrun simctl list runtimes
fi

echo "===== 准备上游源码 ====="
python3 -I scripts/prepare.py all --tags auto

echo "===== 生成 Xcode 工程 ====="
xcodegen generate
python3 -I scripts/prepare.py resolved --project Hub.xcodeproj

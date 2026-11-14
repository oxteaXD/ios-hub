#!/bin/bash
# 在 iOS 模拟器里跑宿主壳的界面测试。在 macOS 上运行，运行前需要先执行 scripts/ci_setup.sh。
#
# 测试内容见 UITests/HubUITests.swift：从启动页进入各个应用、用悬浮按钮返回和切换、
# 启动时直接进入上次使用的应用、收到某个应用的链接时切换过去、EhPanda 主页的「AI 热门」入口等。
# 测试结果和各界面上的文字收集进 build/smoke/result.txt。
#
# 只有 result.txt 会作为构建产物上传。截图和完整的测试日志都留在运行器上不上传：
# 测试会进入 EhPanda 的主页，这两样东西里可能带有站点内容，而公开仓库的构建产物谁都能下载。
#
# 这个测试不登录，只能发现启动、切换和页面跳转的问题，浏览、下载这些功能测不到。
set -euo pipefail

cd "$(dirname "$0")/.."

SCHEME="Hub"
PROJECT="Hub.xcodeproj"
DERIVED_DATA="build/DerivedData-sim"
LOG="build/xcodebuild-sim.log"
XCRESULT="build/HubUITests.xcresult"
OUT="build/smoke"
RESULT="${OUT}/result.txt"

rm -rf "$OUT" "$XCRESULT"
mkdir -p "$OUT"
: > "$RESULT"
# 之后只看比这个文件新的崩溃报告。
MARKER="${OUT}/.started"
touch "$MARKER"

note() {
    echo "$1" | tee -a "$RESULT"
}

# ---------------------------------------------------------------------------
# 选一台模拟器：用现成的 iPhone，优先普通直板机型（折叠屏之类的特殊机型排在后面），
# 同等条件下取系统版本最新的；一台都没有就新建。
# ---------------------------------------------------------------------------
UDID="$(xcrun simctl list devices available -j | python3 -I -c '
import json, re, sys
candidates = []
for runtime, entries in json.load(sys.stdin)["devices"].items():
    if "iOS" not in runtime:
        continue
    for entry in entries:
        name = entry["name"]
        if not entry.get("isAvailable") or not name.startswith("iPhone"):
            continue
        if name == "iPhone Air":
            rank = 3
        elif re.match(r"iPhone \d+", name):
            rank = 2
        else:
            rank = 1
        candidates.append((rank, runtime, name, entry["udid"]))
candidates.sort()
print(candidates[-1][3] if candidates else "")
')"

if [ -z "$UDID" ]; then
    echo "没有现成的 iPhone 模拟器，新建一台"
    RUNTIME="$(xcrun simctl list runtimes -j | python3 -I -c '
import json, sys
runtimes = [r["identifier"] for r in json.load(sys.stdin)["runtimes"] if r.get("isAvailable") and "iOS" in r["identifier"]]
print(sorted(runtimes)[-1] if runtimes else "")
')"
    DEVICE_TYPE="$(xcrun simctl list devicetypes -j | python3 -I -c '
import json, sys
types = [t["identifier"] for t in json.load(sys.stdin)["devicetypes"] if t["name"].startswith("iPhone")]
print(types[-1] if types else "")
')"
    if [ -z "$RUNTIME" ] || [ -z "$DEVICE_TYPE" ]; then
        echo "找不到可用的 iOS 运行时或 iPhone 机型，无法跑界面测试"
        exit 1
    fi
    UDID="$(xcrun simctl create "Hub Smoke Test" "$DEVICE_TYPE" "$RUNTIME")"
fi
note "模拟器：$(xcrun simctl list devices | grep "$UDID" | sed -e 's/^[[:space:]]*//')"

# ---------------------------------------------------------------------------
# 编译并运行界面测试。用方案默认的 Debug 配置加具体的模拟器目标，这是最常规的调用方式。
#
# 不要在命令行上覆盖架构相关的设置（ONLY_ACTIVE_ARCH、ARCHS、-sdk 等）：这些覆盖会一并作用到
# 宏插件上，而宏插件是在宿主机 macOS 上编译的，被覆盖后会找不到 SwiftSyntax 系列模块。
# 也不要关掉代码签名：模拟器上 Xcode 会自动做本地签名，界面测试的运行器需要它。
# ---------------------------------------------------------------------------
echo "开始编译并运行界面测试，完整日志写入 ${LOG}"
set +e
xcodebuild test \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,id=${UDID}" \
    -derivedDataPath "$DERIVED_DATA" \
    -resultBundlePath "$XCRESULT" \
    -parallel-testing-enabled NO \
    -skipMacroValidation \
    -skipPackagePluginValidation \
    > "$LOG" 2>&1
STATUS=$?
set -e

FAILED=0
if [ "$STATUS" -ne 0 ]; then
    FAILED=1
fi

# 每个测试用例的结果。日志里的格式是：Test Case '-[HubUITests.HubUITests 用例名]' passed (12.345 seconds).
CASES="$(grep -a -E "Test Case '.*' (passed|failed) " "$LOG" | sed -E "s/^.*Test Case '-\[[^ ]+ ([^]]+)\]' (passed|failed) \(([0-9.]+) seconds\).*/\2  \1（\3 秒）/" | sed -e 's/^passed/通过/' -e 's/^failed/失败/' || true)"
if [ -n "$CASES" ]; then
    note "$CASES"
else
    note "失败  一个测试用例都没有跑起来（xcodebuild 退出码 ${STATUS}）"
    FAILED=1
fi

# 断言失败和编译错误。
PROBLEMS="$(grep -a -E "(: error: |\*\* (BUILD|TEST) FAILED \*\*|Testing failed)" "$LOG" | sed -e 's/^[[:space:]]*//' | awk '!seen[$0]++' | head -n 40 || true)"
if [ -n "$PROBLEMS" ]; then
    note ""
    note "$PROBLEMS"
fi

# 每个界面上的文字。测试里每行以「HUBUI|界面名|文字」的形式打印。
SCREENS="$(grep -a "HUBUI|" "$LOG" | sed -e 's/^.*HUBUI|//' || true)"
if [ -n "$SCREENS" ]; then
    note ""
    note "各界面上的文字："
    echo "$SCREENS" | awk -F'|' '
        $1 != current { current = $1; printf "\n[%s]\n", current }
        { text = $0; sub(/^[^|]*\|/, "", text); printf "    %s\n", text }
    ' | tee -a "$RESULT"
fi

# ---------------------------------------------------------------------------
# 崩溃报告：测试通过也可能是 App 崩了之后被重新拉起，所以单独再查一遍。
# ---------------------------------------------------------------------------
sleep 5  # 系统写出崩溃报告要几秒
REPORTS="$(find "${HOME}/Library/Logs/DiagnosticReports" -name "${SCHEME}-*.ips" -newer "$MARKER" 2>/dev/null | sort || true)"
if [ -n "$REPORTS" ]; then
    FAILED=1
    note ""
    note "失败  发现崩溃报告："
    echo "$REPORTS" | while IFS= read -r report; do
        note "---- $(basename "$report") ----"
        python3 -I - "$report" <<'PY' | tee -a "$RESULT" || head -n 60 "$report" | tee -a "$RESULT"
import json, sys

text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
# 报告的第一行是一段 JSON 摘要，其余部分是正文 JSON。
body = json.loads(text.split("\n", 1)[1])
exception = body.get("exception", {})
print("异常：", exception.get("type"), exception.get("signal"), exception.get("subtype", ""))
termination = body.get("termination", {})
if termination:
    print("终止原因：", termination.get("namespace"), termination.get("indicator", ""), termination.get("details", ""))
for key in ("asi", "ktriageinfo"):
    if body.get(key):
        print(key + "：", json.dumps(body[key], ensure_ascii=False)[:600])
images = body.get("usedImages", [])
thread = next((t for t in body.get("threads", []) if t.get("triggered")), None)
if thread:
    print("崩溃线程的调用栈（最多 30 帧）：")
    for index, frame in enumerate(thread.get("frames", [])[:30]):
        image = images[frame["imageIndex"]].get("name", "?") if frame.get("imageIndex", -1) < len(images) else "?"
        print("  %2d  %-28s %s" % (index, image, frame.get("symbol", hex(frame.get("imageOffset", 0)))))
PY
    done
fi

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
        if [ "$FAILED" -eq 0 ]; then echo "### 界面测试通过"; else echo "### 界面测试失败"; fi
        echo
        echo '```'
        cat "$RESULT"
        echo '```'
    } >> "$GITHUB_STEP_SUMMARY"
fi

if [ "$FAILED" -ne 0 ]; then
    echo "界面测试失败"
    exit 1
fi
echo "界面测试通过"

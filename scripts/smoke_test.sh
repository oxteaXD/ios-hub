#!/bin/bash
# 在 iOS 模拟器里跑宿主壳的界面测试。在 macOS 上运行，运行前需要先执行 scripts/ci_setup.sh。
#
# 测试内容见 UITests/HubUITests.swift：从启动页进入各个应用、用悬浮按钮返回和切换、
# 启动时直接进入上次使用的应用、收到某个应用的链接时切换过去、EhPanda 主页的「AI 热门」入口等。
# 测试结果和各界面上的文字收集进 build/smoke/result.txt。
#
# 编译和运行分两步做。编译不过时摘出编译错误；测试一个用例都没跑完时（多半是模拟器或测试运行器
# 没能启动）摘出 xcodebuild 给的原因，把模拟器抹掉重启后再试一次。
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
BUILD_LOG="build/xcodebuild-sim-build.log"
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
# 每次开始跑测试时更新，用来找出「这一次」留下的崩溃报告。
ATTEMPT_MARKER="${OUT}/.attempt"
touch "$ATTEMPT_MARKER"

note() {
    echo "$1" | tee -a "$RESULT"
}

# 把 result.txt 写进运行页面的摘要。参数是摘要的标题。
write_summary() {
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
        {
            echo "### $1"
            echo
            echo '```'
            cat "$RESULT"
            echo '```'
        } >> "$GITHUB_STEP_SUMMARY"
    fi
}

# 列出比某个标记文件新的崩溃报告。参数：文件名的匹配式、标记文件。
new_crash_reports() {
    find "${HOME}/Library/Logs/DiagnosticReports" -name "$1" -newer "$2" 2>/dev/null | sort || true
}

# 打印一份崩溃报告的要点：异常类型、终止原因和崩溃线程的调用栈。
describe_crash_report() {
    python3 -I - "$1" <<'PY' || head -n 60 "$1"
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
# 编译和运行分成两步。用方案默认的 Debug 配置加具体的模拟器目标，这是最常规的调用方式。
#
# 不要在命令行上覆盖架构相关的设置（ONLY_ACTIVE_ARCH、ARCHS、-sdk 等）：这些覆盖会一并作用到
# 宏插件上，而宏插件是在宿主机 macOS 上编译的，被覆盖后会找不到 SwiftSyntax 系列模块。
# 也不要关掉代码签名：模拟器上 Xcode 会自动做本地签名，界面测试的运行器需要它。
# ---------------------------------------------------------------------------
COMMON_ARGS=(
    -project "$PROJECT"
    -scheme "$SCHEME"
    -destination "platform=iOS Simulator,id=${UDID}"
    -derivedDataPath "$DERIVED_DATA"
    -skipMacroValidation
    -skipPackagePluginValidation
)

echo "开始编译界面测试，完整日志写入 ${BUILD_LOG}"
set +e
xcodebuild build-for-testing "${COMMON_ARGS[@]}" > "$BUILD_LOG" 2>&1
BUILD_STATUS=$?
set -e

if [ "$BUILD_STATUS" -ne 0 ]; then
    note "失败  界面测试没有编译通过（xcodebuild 退出码 ${BUILD_STATUS}）"
    note ""
    # 编译日志里只有编译器和构建系统的输出，没有 App 的界面内容，可以放心摘出来。
    grep -a -E "(error:|\*\* (TEST )?BUILD FAILED \*\*)" "$BUILD_LOG" \
        | sed -e 's/^[[:space:]]*//' | awk '!seen[$0]++' | head -n 60 | tee -a "$RESULT" || true
    note ""
    note "---- 编译日志末尾 ----"
    tail -n 25 "$BUILD_LOG" | tee -a "$RESULT"
    write_summary "界面测试失败"
    echo "界面测试失败"
    exit 1
fi

# 先把模拟器启动好再跑测试：让 xcodebuild 自己去启动，偶尔会等不到模拟器就绪而直接失败。
# bootstatus 会一直等到系统启动完成，所以给它设个上限，免得模拟器卡死时整个作业跟着卡到超时。
boot_simulator() {
    xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
    xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 &
    local pid=$!
    local waited=0
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$waited" -ge 300 ]; then
            kill "$pid" 2>/dev/null || true
            note "提示  模拟器 5 分钟内没有启动完成，照常往下跑测试"
            break
        fi
        sleep 5
        waited=$((waited + 5))
    done
    wait "$pid" 2>/dev/null || true
}

STATUS=0
run_tests() {
    rm -rf "$XCRESULT"
    touch "$ATTEMPT_MARKER"
    set +e
    xcodebuild test-without-building "${COMMON_ARGS[@]}" \
        -resultBundlePath "$XCRESULT" \
        -parallel-testing-enabled NO \
        > "$LOG" 2>&1
    STATUS=$?
    set -e
}

# 跑完的测试用例数。日志里的格式是：Test Case '-[HubUITests.HubUITests 用例名]' passed (12.345 seconds).
finished_case_count() {
    grep -a -c -E "Test Case '.*' (passed|failed) " "$LOG" || true
}

# 测试没能启动时的原因：xcodebuild 在「Testing failed:」后面给出的那一段、日志里的报错行，
# 以及测试运行器自己的崩溃报告。
# 只在一个用例都没跑完时使用。摘的都是 xcodebuild 和系统给出的信息，不含 App 界面上的内容。
startup_failure_reason() {
    LC_ALL=C awk '
        /Testing failed:/ { printing = 1 }
        printing { print }
        /\*\* TEST (EXECUTE )?FAILED \*\*/ { printing = 0 }
    ' "$LOG" | LC_ALL=C sed -e 's/^[[:space:]]*//' | LC_ALL=C awk 'NF && !seen[$0]++' | head -n 25 || true
    grep -a -E "(^|: )error: " "$LOG" | LC_ALL=C awk '!seen[$0]++' | head -n 15 || true
    sleep 5  # 系统写出崩溃报告要几秒
    new_crash_reports "*Runner*.ips" "$ATTEMPT_MARKER" | while IFS= read -r report; do
        echo "---- $(basename "$report") ----"
        describe_crash_report "$report" || true
    done || true
}

echo "开始运行界面测试，完整日志写入 ${LOG}"
boot_simulator
run_tests

if [ "$(finished_case_count)" -eq 0 ]; then
    note "提示  第一次运行时一个测试用例都没有跑完（xcodebuild 退出码 ${STATUS}），原因如下："
    startup_failure_reason | tee -a "$RESULT" || true
    note "提示  把模拟器关机、抹掉数据后重新启动，再试一次"
    xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
    xcrun simctl erase "$UDID" >/dev/null 2>&1 || true
    boot_simulator
    run_tests
    note ""
fi

FAILED=0
if [ "$STATUS" -ne 0 ]; then
    FAILED=1
fi

CASES="$(grep -a -E "Test Case '.*' (passed|failed) " "$LOG" | sed -E "s/^.*Test Case '-\[[^ ]+ ([^]]+)\]' (passed|failed) \(([0-9.]+) seconds\).*/\2  \1（\3 秒）/" | sed -e 's/^passed/通过/' -e 's/^failed/失败/' || true)"
if [ -n "$CASES" ]; then
    note "$CASES"
else
    note "失败  重试之后还是一个测试用例都没有跑完（xcodebuild 退出码 ${STATUS}），原因如下："
    startup_failure_reason | tee -a "$RESULT" || true
    FAILED=1
fi

# 断言失败的说明。
PROBLEMS="$(grep -a -E "(: error: |\*\* TEST (EXECUTE )?FAILED \*\*)" "$LOG" | sed -e 's/^[[:space:]]*//' | awk '!seen[$0]++' | head -n 40 || true)"
if [ -n "$PROBLEMS" ] && [ -n "$CASES" ]; then
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
REPORTS="$(new_crash_reports "${SCHEME}-*.ips" "$MARKER")"
if [ -n "$REPORTS" ]; then
    FAILED=1
    note ""
    note "失败  发现崩溃报告："
    echo "$REPORTS" | while IFS= read -r report; do
        note "---- $(basename "$report") ----"
        describe_crash_report "$report" | tee -a "$RESULT" || true
    done
fi

if [ "$FAILED" -ne 0 ]; then
    write_summary "界面测试失败"
    echo "界面测试失败"
    exit 1
fi
write_summary "界面测试通过"
echo "界面测试通过"

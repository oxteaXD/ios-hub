#!/bin/bash
# 在 iOS 模拟器里做冒烟测试。在 macOS 上运行，运行前需要先执行 scripts/ci_setup.sh。
#
# 用几种方式启动 App，每种都确认进程过一会儿仍然存活，并截一张图：
#   launcher  默认启动，停在启动页
#   ehpanda   启动后直接进入 EhPanda
#   pixiv     启动后直接进入 Pixiv
#   switch    停在 Pixiv 时收到 EhPanda 的链接，由宿主切换到 EhPanda
#
# 「启动后直接进入某个应用」靠的是偏好设置的命令行参数（-键 值）临时覆盖，不需要改代码。
# 这个测试只能发现启动和切换时的崩溃，登录、浏览、下载这些要联网的功能测不到。
set -euo pipefail

cd "$(dirname "$0")/.."

SCHEME="Hub"
PROJECT="Hub.xcodeproj"
BUNDLE_ID="dev.hubapp.Hub"
DERIVED_DATA="build/DerivedData-sim"
LOG="build/xcodebuild-sim.log"
OUT="build/smoke"
RESULT="${OUT}/result.txt"
WAIT_SECONDS="${SMOKE_WAIT_SECONDS:-15}"

rm -rf "$OUT"
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
        echo "找不到可用的 iOS 运行时或 iPhone 机型，无法做冒烟测试"
        exit 1
    fi
    UDID="$(xcrun simctl create "Hub Smoke Test" "$DEVICE_TYPE" "$RUNTIME")"
fi
note "模拟器：$(xcrun simctl list devices | grep "$UDID" | sed -e 's/^[[:space:]]*//')"

# ---------------------------------------------------------------------------
# 编译模拟器版本。用 Debug 配置加具体的模拟器目标，这是最常规的调用方式。
#
# 不要在命令行上覆盖架构相关的设置（ONLY_ACTIVE_ARCH、ARCHS、-sdk 等）：这些覆盖会一并作用到
# 宏插件上，而宏插件是在宿主机 macOS 上编译的，被覆盖后会找不到 SwiftSyntax 系列模块。
# Debug 配置本来就只编当前架构，不需要覆盖。
# ---------------------------------------------------------------------------
echo "开始编译模拟器版本，完整日志写入 ${LOG}"
set +e
xcodebuild build \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=${UDID}" \
    -derivedDataPath "$DERIVED_DATA" \
    -skipMacroValidation \
    -skipPackagePluginValidation \
    CODE_SIGNING_ALLOWED=NO \
    > "$LOG" 2>&1
STATUS=$?
set -e
if [ "$STATUS" -ne 0 ]; then
    note "失败  模拟器版本编译不过（xcodebuild 退出码 ${STATUS}）"
    grep -E "(error:|fatal error|\*\* BUILD FAILED \*\*)" "$LOG" | sed -e 's/^[[:space:]]*//' | awk '!seen[$0]++' | head -n 60 | tee -a "$RESULT" || true
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
        { echo "### 冒烟测试：模拟器版本编译失败"; echo; echo '```'; cat "$RESULT"; echo '```'; } >> "$GITHUB_STEP_SUMMARY"
    fi
    exit "$STATUS"
fi

APP="${DERIVED_DATA}/Build/Products/Debug-iphonesimulator/${SCHEME}.app"
if [ ! -d "$APP" ]; then
    note "失败  找不到模拟器版本的构建产物 ${APP}"
    exit 1
fi

echo "启动模拟器并安装"
xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl install "$UDID" "$APP"

# ---------------------------------------------------------------------------
# 各种启动方式
# ---------------------------------------------------------------------------
FAILED=0
APP_PID=""

launch_app() {
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
    sleep 1
    local output
    if output="$(xcrun simctl launch "$UDID" "$BUNDLE_ID" "$@" 2>&1)"; then
        # 输出形如「dev.hubapp.Hub: 12345」，冒号后面是进程号。
        APP_PID="${output##*: }"
    else
        note "提示  启动命令本身报错：${output}"
        APP_PID=""
    fi
}

check_case() {
    local name="$1"
    xcrun simctl io "$UDID" screenshot "${OUT}/${name}.png" >/dev/null 2>&1 || true
    if [ -n "$APP_PID" ] && kill -0 "$APP_PID" 2>/dev/null; then
        note "通过  ${name}"
    else
        note "失败  ${name}（App 进程已经退出）"
        FAILED=1
    fi
}

# 界面语言固定成简体中文：顺便检验各模块的中文文案能不能正常显示。
LANGUAGE_ARGS=(-AppleLanguages "(zh-Hans)" -AppleLocale zh_CN)

launch_app "${LANGUAGE_ARGS[@]}" -hub.autoEnterLastModule NO
sleep "$WAIT_SECONDS"
check_case launcher

launch_app "${LANGUAGE_ARGS[@]}" -hub.autoEnterLastModule YES -hub.lastModule ehpanda
sleep "$WAIT_SECONDS"
check_case ehpanda

launch_app "${LANGUAGE_ARGS[@]}" -hub.autoEnterLastModule YES -hub.lastModule pixiv
sleep "$WAIT_SECONDS"
check_case pixiv

# 仍停在 Pixiv：投递一个 EhPanda 的链接，宿主应当切到 EhPanda。
xcrun simctl openurl "$UDID" "ehpanda://hub-smoke-test" >/dev/null 2>&1 || note "提示  向模拟器投递链接失败"
sleep 8
check_case switch

xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# 崩溃报告：进程没退出也可能是崩了之后被系统重新拉起，所以单独再查一遍。
# ---------------------------------------------------------------------------
sleep 5  # 系统写出崩溃报告要几秒
REPORTS="$(find "${HOME}/Library/Logs/DiagnosticReports" -name "${SCHEME}*.ips" -newer "$MARKER" 2>/dev/null | sort || true)"
if [ -n "$REPORTS" ]; then
    FAILED=1
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
    echo "===== App 最近的错误日志 ====="
    xcrun simctl spawn "$UDID" log show --last 3m --style compact \
        --predicate "process == \"${SCHEME}\" AND (messageType == fault OR messageType == error)" 2>/dev/null \
        | tail -n 40 | tee -a "$RESULT" || true
fi

xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# 把每张截图上的文字识别出来写进结果：进程活着不代表界面是对的。
# 识别跑不通不算测试失败，只是少一份参考。
# ---------------------------------------------------------------------------
SHOTS=()
for name in launcher ehpanda pixiv switch; do
    if [ -f "${OUT}/${name}.png" ]; then
        SHOTS+=("${OUT}/${name}.png")
    fi
done
if [ "${#SHOTS[@]}" -gt 0 ]; then
    note ""
    if ! xcrun swift scripts/ocr.swift "${SHOTS[@]}" 2>"${OUT}/ocr-errors.txt" | tee -a "$RESULT"; then
        note "提示  截图的文字识别没有跑通：$(tail -n 3 "${OUT}/ocr-errors.txt" | tr '\n' ' ')"
    fi
fi

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
        if [ "$FAILED" -eq 0 ]; then echo "### 冒烟测试通过"; else echo "### 冒烟测试失败"; fi
        echo
        echo '```'
        cat "$RESULT"
        echo '```'
    } >> "$GITHUB_STEP_SUMMARY"
fi

if [ "$FAILED" -ne 0 ]; then
    echo "冒烟测试失败"
    exit 1
fi
echo "冒烟测试通过"

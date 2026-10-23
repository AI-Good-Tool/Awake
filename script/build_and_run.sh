#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/app-config.sh"
MODE="${1:-run}"
case "${MODE}" in
    run|--debug|--logs|--telemetry|--verify) ;;
    *) echo "Usage: $0 [--debug|--logs|--telemetry|--verify]" >&2; exit 2 ;;
esac

# Graceful termination lets the supervisor and closed-lid watchdog restore sleep.
if pgrep -x "Lidwake" >/dev/null; then
    echo "请先从菜单栏退出旧版 Lidwake，再运行${APP_NAME}。" >&2
    exit 1
fi
if pgrep -x "${EXECUTABLE_NAME}" >/dev/null; then
    /usr/bin/osascript -e "tell application id \"${BUNDLE_ID}\" to quit"
    for attempt in {1..50}; do
        pgrep -x "${EXECUTABLE_NAME}" >/dev/null || break
        sleep 0.1
    done
    if pgrep -x "${EXECUTABLE_NAME}" >/dev/null; then
        echo "应用仍在退出中，请稍后重试。" >&2
        exit 1
    fi
fi

BUILD_CONFIGURATION=debug bash "${ROOT_DIR}/scripts/package-local.sh"
APP_BUNDLE="${ROOT_DIR}/dist/${APP_NAME}.app"
case "${MODE}" in
    --debug) lldb -- "${APP_BUNDLE}/Contents/MacOS/${EXECUTABLE_NAME}" ;;
    *)
        /usr/bin/open -n "${APP_BUNDLE}"
        case "${MODE}" in
            --logs|--telemetry) tail -F "${HOME}/Library/Logs/${EXECUTABLE_NAME}.log" ;;
            --verify) sleep 2; pgrep -x "${EXECUTABLE_NAME}" >/dev/null ;;
        esac
        ;;
esac

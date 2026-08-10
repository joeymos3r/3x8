#!/usr/bin/env bash
set -euo pipefail

PANEL_PORT="${XUI_PORT:-${PORT:-3000}}"
export XUI_PORT="${PANEL_PORT}"

mkdir -p /etc/x-ui /root/cert

echo "Starting 3x-ui..."
echo "Panel port: ${PANEL_PORT}"

# Start 3x-ui first; provision.sh waits for the local panel.
exec /opt/3x-ui/x-ui &
XUI_PID=$!

cleanup() {
    kill "${XUI_PID}" 2>/dev/null || true
}
trap cleanup INT TERM EXIT

# Give the panel a chance to initialize.
for _ in $(seq 1 90); do
    if curl -fsS "http://127.0.0.1:${PANEL_PORT}/" >/dev/null 2>&1; then
        break
    fi

    if ! kill -0 "${XUI_PID}" 2>/dev/null; then
        echo "3x-ui exited before becoming ready." >&2
        wait "${XUI_PID}" || true
        exit 1
    fi

    sleep 2
done

/opt/3x-ui/provision.sh

wait "${XUI_PID}"

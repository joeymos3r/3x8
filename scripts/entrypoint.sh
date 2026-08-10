#!/usr/bin/env bash
set -euo pipefail

PANEL_PORT="${XUI_PORT:-${PORT:-3000}}"
export XUI_PORT="${PANEL_PORT}"

mkdir -p /etc/x-ui /root/cert

echo "Starting 3x-ui on port ${PANEL_PORT}..."

# Railway volumes survive redeploys. If credentials are supplied, make the
# database credentials match them BEFORE starting the web server. This avoids
# the common 403 loop where XUI_USERNAME/XUI_PASSWORD belong to a newer deploy
# but the persisted SQLite database still contains the old account.
if [[ -n "${XUI_USERNAME:-}" && -n "${XUI_PASSWORD:-}" ]]; then
    echo "Applying XUI_USERNAME/XUI_PASSWORD to the persisted 3x-ui database..."
    /opt/3x-ui/x-ui setting \
      -username "${XUI_USERNAME}" \
      -password "${XUI_PASSWORD}" \
      -port "${PANEL_PORT}" \
      -webBasePath "${XUI_WEB_BASE_PATH:-/}" >/dev/null
else
    # On a completely new volume, keep the documented admin/admin fallback.
    if [[ ! -f /etc/x-ui/x-ui.db ]]; then
        /opt/3x-ui/x-ui setting \
          -username "admin" \
          -password "admin" \
          -port "${PANEL_PORT}" \
          -webBasePath "${XUI_WEB_BASE_PATH:-/}" >/dev/null 2>&1
    fi
fi

/opt/3x-ui/x-ui &
XUI_PID=$!

cleanup() {
    kill "${XUI_PID}" 2>/dev/null || true
}
trap cleanup INT TERM EXIT

for _ in $(seq 1 90); do
    if curl -fsS --max-time 3 "http://127.0.0.1:${PANEL_PORT}/" >/dev/null 2>&1; then
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

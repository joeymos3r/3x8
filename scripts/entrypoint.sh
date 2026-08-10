#!/usr/bin/env bash

set -u

# ============================================================
# 3x-ui Railway Entrypoint
# ============================================================

PANEL_PORT="${XUI_PORT:-${PORT:-3000}}"

export XUI_PORT="${PANEL_PORT}"
export XUI_DB_FOLDER="${XUI_DB_FOLDER:-/etc/x-ui}"

DATA_DIR="${XUI_DB_FOLDER}"

PANEL_URL="http://127.0.0.1:${PANEL_PORT}/"

mkdir -p "${DATA_DIR}"
mkdir -p /root/cert
mkdir -p /var/log/x-ui
mkdir -p /tmp

echo "=========================================="
echo " Starting 3x-ui"
echo " Port: ${PANEL_PORT}"
echo " DB: ${DATA_DIR}"
echo " URL: ${PANEL_URL}"
echo "=========================================="

# ============================================================
# Configure credentials
# ============================================================

if [[ -n "${XUI_USERNAME:-}" && -n "${XUI_PASSWORD:-}" ]]; then

    echo "[1/5] Configuring XUI credentials..."

    /opt/3x-ui/x-ui setting \
        -username "${XUI_USERNAME}" \
        -password "${XUI_PASSWORD}" \
        -port "${PANEL_PORT}" \
        -webBasePath "${XUI_WEB_BASE_PATH:-/}" \
        >/tmp/xui-setting.log 2>&1

    SETTING_EXIT=$?

    if [[ "${SETTING_EXIT}" -eq 0 ]]; then

        echo "Credentials configured successfully."

    else

        echo "WARNING: x-ui setting returned ${SETTING_EXIT}"
        cat /tmp/xui-setting.log || true

        echo "Continuing with existing database settings."

    fi

else

    echo "[1/5] XUI_USERNAME/XUI_PASSWORD not set."

    if [[ ! -f "${DATA_DIR}/x-ui.db" ]]; then

        echo "No existing database found."
        echo "Creating initial admin credentials..."

        /opt/3x-ui/x-ui setting \
            -username "admin" \
            -password "admin" \
            -port "${PANEL_PORT}" \
            -webBasePath "${XUI_WEB_BASE_PATH:-/}" \
            >/tmp/xui-setting.log 2>&1

        SETTING_EXIT=$?

        if [[ "${SETTING_EXIT}" -ne 0 ]]; then

            echo "WARNING: failed to initialize credentials."

            cat /tmp/xui-setting.log || true

        else

            echo "Default credentials created."

        fi

    else

        echo "Existing database detected."
        echo "Keeping existing panel credentials."

    fi

fi

# ============================================================
# Start 3x-ui
# ============================================================

echo "[2/5] Starting 3x-ui..."

# Kill old instance if somehow still exists
pkill -f "/opt/3x-ui/x-ui" 2>/dev/null || true

sleep 1

/opt/3x-ui/x-ui > /tmp/xui-runtime.log 2>&1 &

XUI_PID=$!

echo "3x-ui PID: ${XUI_PID}"

# ============================================================
# Cleanup
# ============================================================

cleanup() {

    echo ""
    echo "Stopping 3x-ui..."

    if [[ -n "${XUI_PID:-}" ]]; then

        if kill -0 "${XUI_PID}" 2>/dev/null; then

            kill "${XUI_PID}" 2>/dev/null || true

        fi

    fi

}

trap cleanup INT TERM EXIT

# ============================================================
# Wait for actual HTTP availability
# ============================================================

echo "[3/5] Waiting for 3x-ui web panel..."

READY=0

for i in $(seq 1 120); do

    # Check process first
    if ! kill -0 "${XUI_PID}" 2>/dev/null; then

        echo "ERROR: 3x-ui process died."

        echo "----- x-ui runtime log -----"

        cat /tmp/xui-runtime.log 2>/dev/null || true

        echo "----------------------------"

        exit 1

    fi

    # Real HTTP check
    HTTP_CODE="$(
        curl \
            -sS \
            -o /tmp/xui-health-response \
            -w "%{http_code}" \
            --connect-timeout 2 \
            --max-time 5 \
            "${PANEL_URL}" \
            2>/dev/null || true
    )"

    echo "Panel check ${i}/120 -> HTTP ${HTTP_CODE}"

    # Any real HTTP response means the web server is alive.
    if [[ "${HTTP_CODE}" =~ ^[1-5][0-9][0-9]$ ]]; then

        READY=1

        echo "=========================================="
        echo "3x-ui web panel is READY."
        echo "HTTP: ${HTTP_CODE}"
        echo "=========================================="

        break

    fi

    sleep 1

done

# ============================================================
# Panel failed to start
# ============================================================

if [[ "${READY}" != "1" ]]; then

    echo "=========================================="
    echo "ERROR: 3x-ui did not become ready."
    echo "=========================================="

    echo "----- x-ui runtime log -----"

    cat /tmp/xui-runtime.log 2>/dev/null || true

    echo "----------------------------"

    exit 1

fi

# ============================================================
# Extra stabilization delay
# ============================================================

# 3x-ui can open the HTTP listener slightly before
# all internal services are fully initialized.

echo "Waiting 5 seconds for internal services..."

sleep 5

# ============================================================
# Verify panel again
# ============================================================

echo "Verifying panel one more time..."

VERIFY_CODE="$(
    curl \
        -sS \
        -o /tmp/xui-verify-response \
        -w "%{http_code}" \
        --connect-timeout 3 \
        --max-time 5 \
        "${PANEL_URL}" \
        2>/dev/null || true
)"

echo "Final panel HTTP status: ${VERIFY_CODE}"

if [[ ! "${VERIFY_CODE}" =~ ^[1-5][0-9][0-9]$ ]]; then

    echo "WARNING: final panel verification failed."

    echo "x-ui is still running, provisioning will be skipped."

else

    # ========================================================
    # Provision inbounds
    # ========================================================

    echo "[4/5] Running inbound provisioning..."

    if [[ -x "/opt/3x-ui/provision.sh" ]]; then

        /opt/3x-ui/provision.sh

        PROVISION_EXIT=$?

        if [[ "${PROVISION_EXIT}" -eq 0 ]]; then

            echo "=========================================="
            echo "Inbound provisioning completed."
            echo "=========================================="

        else

            echo "=========================================="
            echo "WARNING: inbound provisioning failed."
            echo "Exit code: ${PROVISION_EXIT}"
            echo "3x-ui will continue running."
            echo "=========================================="

        fi

    else

        echo "ERROR: /opt/3x-ui/provision.sh not found."

    fi

fi

# ============================================================
# Online
# ============================================================

echo "[5/5] 3x-ui is ONLINE."

echo "=========================================="
echo " 3x-ui ONLINE"
echo " Port: ${PANEL_PORT}"
echo " URL: ${PANEL_URL}"
echo " PID: ${XUI_PID}"
echo "=========================================="

# ============================================================
# Keep container alive
# ============================================================

while true; do

    if kill -0 "${XUI_PID}" 2>/dev/null; then

        wait "${XUI_PID}"

        EXIT_CODE=$?

        echo "=========================================="
        echo "3x-ui exited."
        echo "Exit code: ${EXIT_CODE}"
        echo "=========================================="

    else

        echo "3x-ui process is not running."

    fi

    echo "Restarting 3x-ui in 3 seconds..."

    sleep 3

    /opt/3x-ui/x-ui > /tmp/xui-runtime.log 2>&1 &

    XUI_PID=$!

    echo "New 3x-ui PID: ${XUI_PID}"

    # Give restarted process time to initialize
    sleep 3

done

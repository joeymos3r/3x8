#!/usr/bin/env bash

set -u

PANEL_PORT="${XUI_PORT:-${PORT:-3000}}"

export XUI_PORT="${PANEL_PORT}"
export XUI_DB_FOLDER="${XUI_DB_FOLDER:-/etc/x-ui}"
export XUI_DATA_DIR="${XUI_DATA_DIR:-${XUI_DB_FOLDER}}"

DATA_DIR="${XUI_DB_FOLDER}"

mkdir -p "${DATA_DIR}"
mkdir -p /root/cert
mkdir -p /var/log/x-ui

echo "=========================================="
echo " Starting 3x-ui"
echo " Port: ${PANEL_PORT}"
echo " DB: ${DATA_DIR}"
echo "=========================================="

if [[ -n "${XUI_USERNAME:-}" && -n "${XUI_PASSWORD:-}" ]]; then

    echo "[1/5] Configuring XUI credentials..."

    /opt/3x-ui/x-ui setting \
        -username "${XUI_USERNAME}" \
        -password "${XUI_PASSWORD}" \
        -port "${PANEL_PORT}" \
        -webBasePath "${XUI_WEB_BASE_PATH:-/}" \
        >/tmp/xui-setting.log 2>&1

    SETTING_EXIT=$?

    if [[ "${SETTING_EXIT}" -ne 0 ]]; then
        echo "WARNING: x-ui setting returned ${SETTING_EXIT}"
        cat /tmp/xui-setting.log || true
    else
        echo "XUI credentials configured."
    fi

else

    echo "[1/5] XUI_USERNAME/XUI_PASSWORD not set."

    if [[ ! -f "${DATA_DIR}/x-ui.db" ]]; then

        echo "New database detected."
        echo "Creating admin/admin credentials..."

        /opt/3x-ui/x-ui setting \
            -username "admin" \
            -password "admin" \
            -port "${PANEL_PORT}" \
            -webBasePath "${XUI_WEB_BASE_PATH:-/}" \
            >/tmp/xui-setting.log 2>&1

        SETTING_EXIT=$?

        if [[ "${SETTING_EXIT}" -ne 0 ]]; then
            echo "WARNING: unable to initialize credentials."
            cat /tmp/xui-setting.log || true
        fi

    else

        echo "Existing database detected."
        echo "Keeping existing credentials."

    fi

fi

echo "[2/5] Starting 3x-ui..."

 /opt/3x-ui/x-ui &
XUI_PID=$!

echo "3x-ui PID: ${XUI_PID}"

cleanup() {
    echo "Stopping 3x-ui..."

    if kill -0 "${XUI_PID}" 2>/dev/null; then
        kill "${XUI_PID}" 2>/dev/null || true
    fi
}

trap cleanup INT TERM

echo "[3/5] Waiting for 3x-ui..."

READY=0

for i in $(seq 1 90); do

    if ! kill -0 "${XUI_PID}" 2>/dev/null; then

        echo "ERROR: 3x-ui exited during startup."

        wait "${XUI_PID}" 2>/dev/null || true

        echo "Restarting..."

        /opt/3x-ui/x-ui &
        XUI_PID=$!

        sleep 2

        continue

    fi

    HTTP_CODE="$(
        curl \
            -s \
            -o /dev/null \
            -w "%{http_code}" \
            --connect-timeout 2 \
            --max-time 3 \
            "http://127.0.0.1:${PANEL_PORT}/" \
            2>/dev/null || echo "000"
    )"

    if [[ "${HTTP_CODE}" != "000" ]]; then

        READY=1

        echo "3x-ui is READY. HTTP ${HTTP_CODE}"

        break

    fi

    echo "Waiting for panel... ${i}/90"

    sleep 2

done

if [[ "${READY}" == "1" ]]; then

    echo "[4/5] Running inbound provisioning..."

    /opt/3x-ui/provision.sh

    PROVISION_EXIT=$?

    if [[ "${PROVISION_EXIT}" -eq 0 ]]; then
        echo "Inbound provisioning finished."
    else
        echo "WARNING: provisioning returned ${PROVISION_EXIT}."
        echo "3x-ui will continue running."
    fi

else

    echo "WARNING: panel did not become ready."
    echo "Skipping provisioning."

fi

echo "[5/5] 3x-ui is ONLINE."

echo "=========================================="
echo " 3x-ui ONLINE"
echo " Port: ${PANEL_PORT}"
echo "=========================================="

while true; do

    if kill -0 "${XUI_PID}" 2>/dev/null; then

        wait "${XUI_PID}"

        EXIT_CODE=$?

        echo "3x-ui exited with code ${EXIT_CODE}"

    else

        echo "3x-ui process is not running."

    fi

    echo "Restarting 3x-ui in 3 seconds..."

    sleep 3

    /opt/3x-ui/x-ui &
    XUI_PID=$!

done

#!/usr/bin/env bash

set -u

PANEL_PORT="${XUI_PORT:-${PORT:-3000}}"

export XUI_PORT="${PANEL_PORT}"
export XUI_DB_FOLDER="${XUI_DB_FOLDER:-/etc/x-ui}"

DATA_DIR="${XUI_DB_FOLDER}"

mkdir -p "${DATA_DIR}"
mkdir -p /root/cert
mkdir -p /var/log/x-ui

echo "=========================================="
echo " Starting 3x-ui"
echo " Port: ${PANEL_PORT}"
echo " DB: ${DATA_DIR}"
echo "=========================================="

# --------------------------------------------------
# Configure credentials BEFORE starting 3x-ui
# --------------------------------------------------

if [[ -n "${XUI_USERNAME:-}" && -n "${XUI_PASSWORD:-}" ]]; then

    echo "[1/5] Applying Railway XUI credentials..."

    /opt/3x-ui/x-ui setting \
        -username "${XUI_USERNAME}" \
        -password "${XUI_PASSWORD}" \
        -port "${PANEL_PORT}" \
        -webBasePath "${XUI_WEB_BASE_PATH:-/}" \
        >/tmp/xui-setting.log 2>&1

    SETTING_EXIT=$?

    if [[ "${SETTING_EXIT}" -ne 0 ]]; then
        echo "WARNING: x-ui setting command returned ${SETTING_EXIT}"
        cat /tmp/xui-setting.log || true
        echo "Continuing anyway..."
    else
        echo "Credentials applied."
    fi

else

    echo "[1/5] XUI_USERNAME/XUI_PASSWORD not provided."

    if [[ ! -f "${DATA_DIR}/x-ui.db" ]]; then

        echo "New database detected."
        echo "Creating default admin/admin credentials..."

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
        echo "Keeping existing panel credentials."

    fi

fi

# --------------------------------------------------
# Start 3x-ui
# --------------------------------------------------

echo "[2/5] Starting 3x-ui..."

/opt/3x-ui/x-ui &
XUI_PID=$!

echo "3x-ui PID: ${XUI_PID}"

# --------------------------------------------------
# Cleanup
# --------------------------------------------------

cleanup() {

    echo "Stopping 3x-ui..."

    if kill -0 "${XUI_PID}" 2>/dev/null; then
        kill "${XUI_PID}" 2>/dev/null || true
    fi

}

trap cleanup INT TERM

# --------------------------------------------------
# Wait for web panel
# --------------------------------------------------

echo "[3/5] Waiting for 3x-ui web panel..."

READY=0

for i in $(seq 1 90); do

    if curl \
        -fsS \
        --connect-timeout 2 \
        --max-time 3 \
        "http://127.0.0.1:${PANEL_PORT}/" \
        >/dev/null 2>&1
    then

        READY=1

        echo "3x-ui web panel is READY."

        break

    fi

    if ! kill -0 "${XUI_PID}" 2>/dev/null; then

        echo "ERROR: 3x-ui process exited unexpectedly."

        wait "${XUI_PID}" 2>/dev/null || true

        echo "Restarting 3x-ui..."

        /opt/3x-ui/x-ui &
        XUI_PID=$!

    fi

    echo "Waiting for panel... ${i}/90"

    sleep 2

done

# --------------------------------------------------
# Provision inbounds
# --------------------------------------------------

if [[ "${READY}" == "1" ]]; then

    echo "[4/5] Running inbound provisioning..."

    /opt/3x-ui/provision.sh

    PROVISION_EXIT=$?

    if [[ "${PROVISION_EXIT}" -eq 0 ]]; then

        echo "Inbound provisioning completed successfully."

    else

        echo "WARNING: inbound provisioning returned ${PROVISION_EXIT}."
        echo "IMPORTANT: 3x-ui will NOT crash."

    fi

else

    echo "WARNING: panel did not become ready."
    echo "Skipping inbound provisioning."

fi

# --------------------------------------------------
# Keep container alive
# --------------------------------------------------

echo "[5/5] 3x-ui is running."

echo "=========================================="
echo " 3x-ui is ONLINE"
echo " Port: ${PANEL_PORT}"
echo "=========================================="

# Wait for x-ui forever.
# If it dies, restart it instead of letting Railway
# immediately restart the whole container.

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

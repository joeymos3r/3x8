#!/usr/bin/env bash
set -euo pipefail

DATA_DIR="${XUI_DATA_DIR:-/etc/x-ui}"
MARKER="${DATA_DIR}/.railway-provisioned"
CONFIG="/opt/3x-ui/config/inbounds.json"

mkdir -p "${DATA_DIR}" /root/cert

if [[ -f "${MARKER}" ]]; then
    echo "Provisioning already completed; leaving existing 3x-ui data unchanged."
    exit 0
fi

if [[ ! -f "${CONFIG}" ]]; then
    echo "Missing ${CONFIG}" >&2
    exit 1
fi

# This configuration file is intentionally descriptive only. It does not
# inject network listeners or proxy-routing rules into the 3x-ui database.
# Use the 3x-ui web panel to create and validate any inbounds you need.
jq -e '.inbounds | type == "array"' "${CONFIG}" >/dev/null

INSTALL_ID="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
cat > "${MARKER}" <<EOF
INSTALL_ID=${INSTALL_ID}
PROVISIONED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
chmod 600 "${MARKER}"

echo "Initial provisioning completed."

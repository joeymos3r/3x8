#!/usr/bin/env bash
set -euo pipefail

XUI_DATA_DIR="${XUI_DATA_DIR:-/etc/x-ui}"
MARKER="${XUI_DATA_DIR}/.railway-provisioned"

mkdir -p "${XUI_DATA_DIR}"
mkdir -p /root/cert

if [[ -f "${MARKER}" ]]; then
    echo "3x-ui provisioning already completed."
    exit 0
fi

if command -v od >/dev/null 2>&1; then
    INSTALL_ID="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
else
    INSTALL_ID="$(date +%s)-$$"
fi

cat > "${MARKER}" <<EOF
INSTALL_ID=${INSTALL_ID}
PROVISIONED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

chmod 600 "${MARKER}"

echo "Initial 3x-ui provisioning completed."
echo "Persistent data directory: ${XUI_DATA_DIR}"

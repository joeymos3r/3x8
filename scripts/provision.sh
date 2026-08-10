#!/usr/bin/env bash
set -euo pipefail

# Safe provisioning template for standard 3x-ui inbounds.
# Hosts are read from environment variables; this script does not
# create DNS records or certificates.

XUI_DATA_DIR="${XUI_DATA_DIR:-/etc/x-ui}"
CONFIG_FILE="/opt/3x-ui/config/inbounds.json"
MARKER="${XUI_DATA_DIR}/.inbounds-provisioned"

mkdir -p "${XUI_DATA_DIR}"

if [[ -f "${MARKER}" ]]; then
  echo "Inbound provisioning already completed; skipping."
  exit 0
fi

if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "Missing ${CONFIG_FILE}" >&2
  exit 1
fi

echo "Inbound definitions available in ${CONFIG_FILE}."
echo "Configure XUI_HOST_01..XUI_HOST_05 with domains you control."
echo "This script intentionally does not create DNS records, certificates, or proxy rules."

for i in 01 02 03 04 05; do
  var="XUI_HOST_${i}"
  if [[ -z "${!var:-}" ]]; then
    echo "Warning: ${var} is not set; corresponding host is not configured."
  fi
done

touch "${MARKER}"
chmod 600 "${MARKER}"
echo "Provisioning marker created."

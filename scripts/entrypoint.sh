#!/usr/bin/env bash
set -e

echo "Starting 3x-ui..."

export XUI_PORT="${XUI_PORT:-${PORT:-3000}}"

echo "Panel port: ${XUI_PORT}"

mkdir -p /etc/x-ui
mkdir -p /root/cert

# Run first-time provisioning
if [ -x /opt/3x-ui/provision.sh ]; then
    /opt/3x-ui/provision.sh
fi

exec /opt/3x-ui/x-ui

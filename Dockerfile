#!/usr/bin/env bash
set -e

echo "Starting 3x-ui..."

# Railway provides PORT at runtime.
# XUI_PORT can be explicitly set in Railway; otherwise use PORT.
export XUI_PORT="${XUI_PORT:-${PORT:-3000}}"

echo "Panel port: ${XUI_PORT}"

# Required directories
mkdir -p /etc/x-ui
mkdir -p /root/cert

# Start 3x-ui
exec /opt/3x-ui/x-ui

#!/usr/bin/env bash
set -e

# Railway provides PORT at runtime.
# Use XUI_PORT when explicitly supplied; otherwise use Railway's PORT.
XUI_PORT="${XUI_PORT:-${PORT:-3000}}"

export XUI_PORT

echo "Starting 3x-ui..."
echo "Panel port: ${XUI_PORT}"

# Create required directories
mkdir -p /etc/x-ui
mkdir -p /root/cert

# Start 3x-ui
exec /opt/3x-ui/x-ui

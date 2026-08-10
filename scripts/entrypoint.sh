#!/bin/bash

set -e

echo "=========================================="
echo "  Starting 3x-ui"
echo "  Port: 3000"
echo "  DB: /etc/x-ui"
echo "  URL: http://127.0.0.1:3000/"
echo "=========================================="

# Start 3x-ui in background
echo "[1/3] Starting 3x-ui..."
/usr/local/x-ui/x-ui start &

# Wait for 3x-ui to be ready
echo "[2/3] Waiting for 3x-ui to be ready..."
for i in {1..60}; do
    if curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:3000/ | grep -q "200\|302\|307"; then
        echo "3x-ui is ready!"
        break
    fi
    sleep 2
done

# Run provisioning
echo "[3/3] Running inbound provisioning..."
if [ -f "/opt/3x-ui/provision.sh" ]; then
    /opt/3x-ui/provision.sh || echo "WARNING: Provisioning failed, but continuing..."
else
    echo "WARNING: provision.sh not found!"
fi

echo "=========================================="
echo "  3x-ui is ONLINE"
echo "  Port: 3000"
echo "  URL: http://127.0.0.1:3000/"
echo "=========================================="

# Keep container running
tail -f /dev/null

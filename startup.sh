#!/bin/sh

set -eu

echo "========================================"
echo " 3x8 / 3x-ui + Xray + Nginx"
echo "========================================"

if [ -f /config.env ]; then
    . /config.env
fi

HTTP_PORT="${HTTP_PORT:-3000}"
XUI_PORT="${XUI_PORT:-2053}"

echo "HTTP PORT : ${HTTP_PORT}"
echo "XUI PORT  : ${XUI_PORT}"
echo "TCP PORT  : ${TCP_PORT:-8080}"

echo ""
echo "[1/5] Checking nginx..."

nginx -t

echo ""
echo "[2/5] Starting 3x-ui..."

if command -v x-ui >/dev/null 2>&1; then
    x-ui &
    XUI_PID=$!
elif [ -x /app/x-ui ]; then
    /app/x-ui &
    XUI_PID=$!
elif [ -x /usr/local/x-ui/x-ui ]; then
    /usr/local/x-ui/x-ui &
    XUI_PID=$!
else
    echo "ERROR: x-ui executable not found."
    exit 1
fi

echo "3x-ui PID: ${XUI_PID}"

echo ""
echo "[3/5] Waiting for 3x-ui..."

READY=0

for i in $(seq 1 60); do
    if curl -fsS \
        --connect-timeout 2 \
        --max-time 3 \
        http://127.0.0.1:${XUI_PORT}/ >/dev/null 2>&1; then

        READY=1
        echo "3x-ui is ready."
        break
    fi

    if ! kill -0 "${XUI_PID}" 2>/dev/null; then
        echo "ERROR: 3x-ui stopped."
        exit 1
    fi

    echo "Waiting for 3x-ui... ${i}/60"
    sleep 1
done

if [ "${READY}" -ne 1 ]; then
    echo "ERROR: 3x-ui did not become ready."
    exit 1
fi

echo ""
echo "[4/5] Starting nginx..."

nginx -g "daemon off;" &
NGINX_PID=$!

echo "nginx PID: ${NGINX_PID}"

echo ""
echo "[5/5] Services running."
echo ""
echo "Panel:"
echo "  /managepanel/"
echo ""
echo "Subscription:"
echo "  /sub/"
echo ""
echo "WebSocket paths:"
echo "  /Cbee1  -> 18080"
echo "  /Cbee2  -> 18081"
echo "  /Cbee3  -> 18082"
echo "  /Cbee4  -> 18083"
echo "  /Cbee5  -> 18084"
echo "  /Cbee6  -> 18085"
echo "  /Cbee7  -> 18086"
echo "  /Cbee8  -> 18087"
echo "  /Cbee9  -> 18088"
echo "  /Cbee10 -> 18089"
echo "  /Cbee11 -> 18090"
echo "  /Cbee12 -> 18091"
echo "  /Cbee13 -> 18092"
echo "  /Cbee14 -> 18093"
echo "  /Cbee15 -> 18094"
echo ""
echo "TCP Proxy target:"
echo "  8080"
echo ""

while true; do

    if ! kill -0 "${XUI_PID}" 2>/dev/null; then
        echo "ERROR: 3x-ui stopped."
        exit 1
    fi

    if ! kill -0 "${NGINX_PID}" 2>/dev/null; then
        echo "ERROR: nginx stopped."
        exit 1
    fi

    sleep 5

done

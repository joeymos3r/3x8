#!/bin/bash

set -e

# Use environment variable or fallback to local
if [ -n "$PANEL_URL" ]; then
    # Use the exact URL provided
    PANEL_BASE="$PANEL_URL"
else
    # Default to local
    PANEL_BASE="http://127.0.0.1:3000/panel"
fi

XUI_USERNAME="${XUI_USERNAME:-admin}"
XUI_PASSWORD="${XUI_PASSWORD:-admin}"
CONFIG_FILE="${CONFIG_FILE:-/opt/3x-ui/config/inbounds.json}"
COOKIE_FILE="/tmp/xui_cookies.txt"

echo "=========================================="
echo "  3x-ui inbound provisioning"
echo "  Panel : $PANEL_BASE"
echo "  User  : $XUI_USERNAME"
echo "  Config: $CONFIG_FILE"
echo "=========================================="

# Check if config exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Config file not found: $CONFIG_FILE"
    exit 1
fi

# Read inbounds
INBOUNDS=$(jq -c '.inbounds[]' "$CONFIG_FILE" 2>/dev/null)
if [ -z "$INBOUNDS" ]; then
    echo "ERROR: No inbounds found in config"
    exit 1
fi

COUNT=$(echo "$INBOUNDS" | wc -l)
echo "Configured inbounds: $COUNT"

# Generate TLS certificate (if needed for SSL)
echo "Generating TLS certificate..."
mkdir -p /etc/x-ui/cert
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -keyout /etc/x-ui/cert/server.key -out /etc/x-ui/cert/server.crt \
    -days 3650 -nodes -subj "/CN=localhost" 2>/dev/null || true
echo "TLS certificate ready."

# Wait for panel
echo ""
echo "Waiting for 3x-ui HTTP server..."
for i in {1..30}; do
    # Try with -k flag for SSL if needed
    HTTP_CODE=$(curl -s -k -o /dev/null -w "%{http_code}" "$PANEL_BASE/login" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
        echo "Panel is responding: HTTP $HTTP_CODE"
        break
    fi
    sleep 2
done

echo "Waiting for panel initialization..."
sleep 3

echo "  3x-ui ONLINE"
echo "  URL: $PANEL_BASE"
echo "=========================================="
echo ""

# Login to panel
echo "Logging in to 3x-ui..."

# Try JSON login
LOGIN_RESPONSE=$(curl -s -k -X POST "$PANEL_BASE/login" \
    -H "Content-Type: application/json" \
    -b "$COOKIE_FILE" \
    -c "$COOKIE_FILE" \
    -d "{\"username\":\"$XUI_USERNAME\",\"password\":\"$XUI_PASSWORD\"}" 2>/dev/null)

HTTP_CODE=$(curl -s -k -o /dev/null -w "%{http_code}" -X POST "$PANEL_BASE/login" \
    -H "Content-Type: application/json" \
    -b "$COOKIE_FILE" \
    -c "$COOKIE_FILE" \
    -d "{\"username\":\"$XUI_USERNAME\",\"password\":\"$XUI_PASSWORD\"}" 2>/dev/null)

echo "Login HTTP status: $HTTP_CODE"

if [ "$HTTP_CODE" != "200" ]; then
    echo ""
    echo "=========================================="
    echo "ERROR: 3x-ui rejected login."
    echo "HTTP: $HTTP_CODE"
    echo "=========================================="
    echo ""
    echo "Current username: $XUI_USERNAME"
    echo "Panel URL: $PANEL_BASE"
    echo ""
    echo "=========================================="
    echo "WARNING: inbound provisioning failed."
    echo "3x-ui will continue running."
    echo "=========================================="
    exit 31
fi

echo "✅ Login successful!"

# Get existing inbounds
EXISTING_INBOUNDS=$(curl -s -k -b "$COOKIE_FILE" "$PANEL_BASE/api/inbounds/list" 2>/dev/null)
EXISTING_PORTS=$(echo "$EXISTING_INBOUNDS" | jq -r '.obj[]?.port' 2>/dev/null)

# Add each inbound
echo ""
echo "Adding inbounds..."
echo "$INBOUNDS" | while read -r inbound; do
    PORT=$(echo "$inbound" | jq -r '.port')
    PROTOCOL=$(echo "$inbound" | jq -r '.protocol')
    
    # Check if port already exists
    if echo "$EXISTING_PORTS" | grep -q "^$PORT$"; then
        echo "⚠️  Port $PORT already exists, skipping..."
        continue
    fi
    
    echo "Adding inbound: $PROTOCOL on port $PORT"
    
    RESPONSE=$(curl -s -k -X POST "$PANEL_BASE/api/inbounds/add" \
        -H "Content-Type: application/json" \
        -b "$COOKIE_FILE" \
        -d "$inbound" 2>/dev/null)
    
    SUCCESS=$(echo "$RESPONSE" | jq -r '.success' 2>/dev/null)
    if [ "$SUCCESS" = "true" ]; then
        echo "✅ Added inbound on port $PORT"
    else
        echo "❌ Failed to add inbound on port $PORT"
        echo "Response: $RESPONSE"
    fi
done

echo ""
echo "=========================================="
echo "✅ Provisioning completed successfully!"
echo "=========================================="

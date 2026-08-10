#!/bin/bash

set -e

echo "=========================================="
echo "  3x-ui inbound provisioning (DB Method)"
echo "=========================================="

# Variables
DB_PATH="/etc/x-ui/x-ui.db"
CONFIG_FILE="/opt/3x-ui/config/inbounds.json"

# Check if config exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Config file not found: $CONFIG_FILE"
    exit 1
fi

# Check if database exists
if [ ! -f "$DB_PATH" ]; then
    echo "ERROR: Database not found: $DB_PATH"
    exit 1
fi

# Install sqlite3 if not installed
if ! command -v sqlite3 &> /dev/null; then
    echo "Installing sqlite3..."
    apt-get update && apt-get install -y sqlite3
fi

# Read inbounds from config
echo "Reading inbounds from config..."
INBOUNDS=$(jq -r '.inbounds[] | @base64' "$CONFIG_FILE" 2>/dev/null)

if [ -z "$INBOUNDS" ]; then
    echo "ERROR: No inbounds found in config"
    exit 1
fi

COUNT=$(echo "$INBOUNDS" | wc -l)
echo "Configured inbounds: $COUNT"

# Get existing ports from database
EXISTING_PORTS=$(sqlite3 "$DB_PATH" "SELECT port FROM inbounds;" 2>/dev/null || echo "")

# Add each inbound
echo ""
echo "Adding inbounds to database..."

echo "$INBOUNDS" | while read -r inbound_b64; do
    # Decode inbound
    inbound=$(echo "$inbound_b64" | base64 -d)
    
    PORT=$(echo "$inbound" | jq -r '.port')
    PROTOCOL=$(echo "$inbound" | jq -r '.protocol')
    SETTINGS=$(echo "$inbound" | jq -c '.settings' | sed "s/'/''/g")
    STREAM_SETTINGS=$(echo "$inbound" | jq -c '.streamSettings' | sed "s/'/''/g")
    SNIFFING=$(echo "$inbound" | jq -c '.sniffing' | sed "s/'/''/g")
    ENABLE=$(echo "$inbound" | jq -r '.enable')
    
    # Convert enable to integer
    if [ "$ENABLE" = "true" ]; then
        ENABLE_INT=1
    else
        ENABLE_INT=0
    fi
    
    # Check if port already exists
    if echo "$EXISTING_PORTS" | grep -q "^$PORT$"; then
        echo "⚠️  Port $PORT already exists, skipping..."
        continue
    fi
    
    echo "Adding inbound: $PROTOCOL on port $PORT"
    
    # Insert into database
    sqlite3 "$DB_PATH" "INSERT INTO inbounds (
        port,
        protocol,
        settings,
        streamSettings,
        sniffing,
        enable,
        created_at,
        updated_at
    ) VALUES (
        $PORT,
        '$PROTOCOL',
        '$SETTINGS',
        '$STREAM_SETTINGS',
        '$SNIFFING',
        $ENABLE_INT,
        datetime('now'),
        datetime('now')
    );" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "✅ Added inbound on port $PORT"
    else
        echo "❌ Failed to add inbound on port $PORT"
    fi
done

echo ""
echo "=========================================="
echo "✅ Provisioning completed successfully!"
echo "=========================================="

# Restart 3x-ui to apply changes
echo "Restarting 3x-ui to apply changes..."
killall -9 x-ui 2>/dev/null || true
/usr/local/x-ui/x-ui start &

echo "Done!"

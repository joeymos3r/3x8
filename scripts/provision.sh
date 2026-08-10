#!/usr/bin/env bash

set -u

# ============================================================
# 3x-ui Railway Inbound Provisioner
# ============================================================

DATA_DIR="${XUI_DB_FOLDER:-${XUI_DATA_DIR:-/etc/x-ui}}"

CONFIG="/opt/3x-ui/config/inbounds.json"

CERT_DIR="${XUI_CERT_DIR:-/root/cert/railway}"

COOKIE_JAR="${DATA_DIR}/.railway-xui-cookie"

PANEL_PORT="${XUI_PORT:-${PORT:-3000}}"

PANEL_BASE_PATH="${XUI_WEB_BASE_PATH:-/}"

BASE_URL="http://127.0.0.1:${PANEL_PORT}"

XUI_USER="${XUI_USERNAME:-admin}"
XUI_PASS="${XUI_PASSWORD:-admin}"

LOGIN_URL="${BASE_URL}/login"

LIST_URL="${BASE_URL}/panel/api/inbounds/list"

ADD_URL="${BASE_URL}/panel/api/inbounds/add"

mkdir -p "${DATA_DIR}"
mkdir -p "${CERT_DIR}"
mkdir -p /tmp

echo ""
echo "=========================================="
echo " 3x-ui inbound provisioning"
echo " Panel : ${BASE_URL}"
echo " User  : ${XUI_USER}"
echo " Config: ${CONFIG}"
echo "=========================================="

# ============================================================
# Check required files
# ============================================================

if [[ ! -f "${CONFIG}" ]]; then

    echo "ERROR: Missing config file:"
    echo "${CONFIG}"

    exit 10

fi

if ! jq -e '.inbounds | type == "array"' "${CONFIG}" >/dev/null 2>&1; then

    echo "ERROR: Invalid inbounds.json"

    cat "${CONFIG}" || true

    exit 11

fi

INBOUND_COUNT="$(
    jq -r '.inbounds | length' "${CONFIG}" 2>/dev/null || echo "0"
)"

echo "Configured inbounds: ${INBOUND_COUNT}"

if [[ "${INBOUND_COUNT}" == "0" ]]; then

    echo "WARNING: inbounds.json contains zero inbounds."

    exit 0

fi

# ============================================================
# Generate TLS certificate
# ============================================================

if [[ ! -s "${CERT_DIR}/cert.pem" || ! -s "${CERT_DIR}/key.pem" ]]; then

    echo "Generating TLS certificate..."

    TLS_NAME="${XUI_TLS_SERVER_NAME:-localhost}"
    TLS_DAYS="${XUI_TLS_CERT_DAYS:-3650}"

    openssl req \
        -x509 \
        -nodes \
        -newkey rsa:2048 \
        -days "${TLS_DAYS}" \
        -keyout "${CERT_DIR}/key.pem" \
        -out "${CERT_DIR}/cert.pem" \
        -subj "/CN=${TLS_NAME}" \
        >/dev/null 2>&1

    if [[ ! -s "${CERT_DIR}/cert.pem" || ! -s "${CERT_DIR}/key.pem" ]]; then

        echo "WARNING: certificate generation failed."

    else

        chmod 600 "${CERT_DIR}/key.pem"

        echo "TLS certificate ready."

    fi

else

    echo "Existing TLS certificate found."

fi

# ============================================================
# Wait until HTTP server really responds
# ============================================================

echo ""
echo "Waiting for 3x-ui HTTP server..."

PANEL_READY=0

for i in $(seq 1 120); do

    HTTP_CODE="$(
        curl \
            -sS \
            -o /tmp/xui-panel-response \
            -w "%{http_code}" \
            --connect-timeout 2 \
            --max-time 5 \
            "${BASE_URL}/" \
            2>/dev/null || true
    )"

    if [[ "${HTTP_CODE}" =~ ^[1-5][0-9][0-9]$ ]]; then

        echo "Panel is responding: HTTP ${HTTP_CODE}"

        PANEL_READY=1

        break

    fi

    echo "Panel not ready yet: ${HTTP_CODE} (${i}/120)"

    sleep 1

done

if [[ "${PANEL_READY}" != "1" ]]; then

    echo ""
    echo "=========================================="
    echo "ERROR: 3x-ui HTTP server is not ready."
    echo "=========================================="

    exit 20

fi

# ============================================================
# Give session/database initialization time
# ============================================================

echo "Waiting for panel initialization..."

sleep 3

# ============================================================
# Clean old cookie
# ============================================================

rm -f "${COOKIE_JAR}"

# ============================================================
# Login
# ============================================================

echo ""
echo "Logging in to 3x-ui..."

LOGIN_JSON="$(
    jq -cn \
        --arg username "${XUI_USER}" \
        --arg password "${XUI_PASS}" \
        '{
            username: $username,
            password: $password
        }'
)"

LOGIN_RESPONSE_FILE="/tmp/xui-login-response.json"
LOGIN_HEADERS_FILE="/tmp/xui-login-headers.txt"

rm -f "${LOGIN_RESPONSE_FILE}"
rm -f "${LOGIN_HEADERS_FILE}"

LOGIN_HTTP_CODE="$(
    curl \
        -sS \
        -o "${LOGIN_RESPONSE_FILE}" \
        -D "${LOGIN_HEADERS_FILE}" \
        -w "%{http_code}" \
        --connect-timeout 5 \
        --max-time 20 \
        -c "${COOKIE_JAR}" \
        -b "${COOKIE_JAR}" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -H "X-Requested-With: XMLHttpRequest" \
        -X POST \
        "${LOGIN_URL}" \
        --data "${LOGIN_JSON}" \
        2>/dev/null || true
)"

LOGIN_RESPONSE="$(
    cat "${LOGIN_RESPONSE_FILE}" 2>/dev/null || true
)"

echo "Login HTTP status: ${LOGIN_HTTP_CODE}"

if [[ -n "${LOGIN_RESPONSE}" ]]; then

    echo "Login response:"
    echo "${LOGIN_RESPONSE}"

fi

# ============================================================
# Login validation
# ============================================================

if [[ "${LOGIN_HTTP_CODE}" == "000" ]]; then

    echo ""
    echo "ERROR: Could not connect to 3x-ui login endpoint."

    rm -f "${COOKIE_JAR}"

    exit 30

fi

if [[ "${LOGIN_HTTP_CODE}" == "401" || "${LOGIN_HTTP_CODE}" == "403" ]]; then

    echo ""
    echo "=========================================="
    echo "ERROR: 3x-ui rejected login."
    echo "HTTP: ${LOGIN_HTTP_CODE}"
    echo "=========================================="
    echo ""
    echo "Current username:"
    echo "${XUI_USER}"
    echo ""
    echo "If Railway has an existing Volume,"
    echo "the database may contain different credentials."
    echo ""

    rm -f "${COOKIE_JAR}"

    exit 31

fi

if [[ "${LOGIN_HTTP_CODE}" != "200" && "${LOGIN_HTTP_CODE}" != "204" ]]; then

    echo ""
    echo "WARNING: unexpected login HTTP status:"
    echo "${LOGIN_HTTP_CODE}"

    rm -f "${COOKIE_JAR}"

    exit 32

fi

LOGIN_SUCCESS="$(
    jq -r '.success // false' \
        <<<"${LOGIN_RESPONSE}" \
        2>/dev/null || echo "false"
)"

if [[ -n "${LOGIN_RESPONSE}" && "${LOGIN_SUCCESS}" != "true" ]]; then

    echo ""
    echo "WARNING: login response does not report success."

    echo "${LOGIN_RESPONSE}"

    # Some 3x-ui builds return a valid session without
    # the exact same JSON structure, so continue only
    # if a session cookie exists.

fi

# ============================================================
# Check session cookie
# ============================================================

if [[ ! -s "${COOKIE_JAR}" ]]; then

    echo ""
    echo "ERROR: Login returned no session cookie."

    echo "Cookie file:"
    cat "${COOKIE_JAR}" 2>/dev/null || true

    exit 33

fi

echo "Session cookie received."

# ============================================================
# Obtain CSRF information
# ============================================================

echo ""
echo "Obtaining CSRF token..."

CSRF_TOKEN=""

CSRF_RESPONSE_FILE="/tmp/xui-csrf-response.json"
CSRF_HEADERS_FILE="/tmp/xui-csrf-headers.txt"

rm -f "${CSRF_RESPONSE_FILE}"
rm -f "${CSRF_HEADERS_FILE}"

CSRF_HTTP_CODE="$(
    curl \
        -sS \
        -o "${CSRF_RESPONSE_FILE}" \
        -D "${CSRF_HEADERS_FILE}" \
        -w "%{http_code}" \
        --connect-timeout 5 \
        --max-time 10 \
        -b "${COOKIE_JAR}" \
        -c "${COOKIE_JAR}" \
        -H "Accept: application/json" \
        -H "X-Requested-With: XMLHttpRequest" \
        "${BASE_URL}/panel/csrf-token" \
        2>/dev/null || true
)"

CSRF_RESPONSE="$(
    cat "${CSRF_RESPONSE_FILE}" 2>/dev/null || true
)"

# Try JSON response
CSRF_TOKEN="$(
    jq -r '
        .obj //
        .token //
        .csrfToken //
        .csrf_token //
        empty
    ' <<<"${CSRF_RESPONSE}" \
    2>/dev/null || true
)"

# Try response headers
if [[ -z "${CSRF_TOKEN}" && -f "${CSRF_HEADERS_FILE}" ]]; then

    CSRF_TOKEN="$(
        awk '
            BEGIN { IGNORECASE=1 }
            /^x-csrf-token:/ {
                sub(/\r$/, "", $0)
                sub(/^[^:]*:[[:space:]]*/, "", $0)
                print
                exit
            }
        ' "${CSRF_HEADERS_FILE}"
    )"

fi

# Try cookie jar
if [[ -z "${CSRF_TOKEN}" && -f "${COOKIE_JAR}" ]]; then

    CSRF_TOKEN="$(
        awk '
            $0 !~ /^#/ && $6 ~ /csrf/i {
                print $7
                exit
            }
        ' "${COOKIE_JAR}"
    )"

fi

if [[ -n "${CSRF_TOKEN}" ]]; then

    echo "CSRF token obtained."

else

    echo "No explicit CSRF token found."

    echo "Continuing; API may accept the authenticated session."

fi

# ============================================================
# Build authentication headers
# ============================================================

AUTH_HEADERS=(
    -b "${COOKIE_JAR}"
    -c "${COOKIE_JAR}"
    -H "Accept: application/json"
    -H "Content-Type: application/json"
    -H "X-Requested-With: XMLHttpRequest"
)

if [[ -n "${CSRF_TOKEN}" ]]; then

    AUTH_HEADERS+=(
        -H "X-CSRF-Token: ${CSRF_TOKEN}"
        -H "X-CSRFToken: ${CSRF_TOKEN}"
    )

fi

# ============================================================
# Read current inbounds
# ============================================================

echo ""
echo "Reading existing inbounds..."

EXISTING_FILE="/tmp/xui-existing-inbounds.json"

EXISTING_HTTP_CODE="$(
    curl \
        -sS \
        -o "${EXISTING_FILE}" \
        -w "%{http_code}" \
        --connect-timeout 5 \
        --max-time 20 \
        "${AUTH_HEADERS[@]}" \
        "${LIST_URL}" \
        2>/dev/null || true
)"

EXISTING="$(
    cat "${EXISTING_FILE}" 2>/dev/null || true
)"

echo "Inbound list HTTP status: ${EXISTING_HTTP_CODE}"

if [[ "${EXISTING_HTTP_CODE}" == "401" || "${EXISTING_HTTP_CODE}" == "403" ]]; then

    echo ""
    echo "ERROR: authenticated inbound request was rejected."

    echo "${EXISTING}"

    exit 40

fi

if [[ "${EXISTING_HTTP_CODE}" != "200" ]]; then

    echo ""
    echo "ERROR: Could not read existing inbounds."

    echo "${EXISTING}"

    exit 41

fi

EXISTING_SUCCESS="$(
    jq -r '.success // false' \
        <<<"${EXISTING}" \
        2>/dev/null || echo "false"
)"

if [[ "${EXISTING_SUCCESS}" != "true" ]]; then

    echo ""
    echo "ERROR: 3x-ui returned unsuccessful inbound list."

    echo "${EXISTING}"

    exit 42

fi

CURRENT_COUNT="$(
    jq -r '
        if (.obj | type) == "array"
        then (.obj | length)
        else 0
        end
    ' <<<"${EXISTING}" \
    2>/dev/null || echo "0"
)"

echo "Existing inbounds: ${CURRENT_COUNT}"

# ============================================================
# Create inbounds
# ============================================================

CREATED=0
EXISTING_COUNT=0
FAILED=0

while IFS= read -r SPEC; do

    [[ -z "${SPEC}" ]] && continue

    NAME="$(
        jq -r '.name // .remark // "unnamed"' \
            <<<"${SPEC}"
    )"

    PORT="$(
        jq -r '.port // 0' \
            <<<"${SPEC}"
    )"

    PROTOCOL="$(
        jq -r '.protocol // "vless"' \
            <<<"${SPEC}"
    )"

    ENABLE="$(
        jq -r '
            if .enable == null
            then true
            else .enable
            end
        ' <<<"${SPEC}"
    )"

    echo ""
    echo "=========================================="
    echo "Inbound: ${NAME}"
    echo "Protocol: ${PROTOCOL}"
    echo "Port: ${PORT}"
    echo "=========================================="

    # ========================================================
    # Validate
    # ========================================================

    if [[ "${PORT}" == "0" || -z "${PORT}" ]]; then

        echo "WARNING: invalid port for ${NAME}"

        FAILED=$((FAILED + 1))

        continue

    fi

    # ========================================================
    # Check existing inbound by remark
    # ========================================================

    ALREADY_EXISTS="$(
        jq \
            -r \
            --arg name "${NAME}" \
            '
            if (.obj | type) == "array"
            then
                any(
                    .obj[];
                    ((.remark // "") == $name)
                )
            else
                false
            end
            ' <<<"${EXISTING}" \
        2>/dev/null || echo "false"
    )"

    if [[ "${ALREADY_EXISTS}" == "true" ]]; then

        echo "Inbound already exists."

        EXISTING_COUNT=$((EXISTING_COUNT + 1))

        continue

    fi

    # ========================================================
    # Build inbound body
    # ========================================================

    BODY="$(
        jq -c \
            --arg cert "${CERT_DIR}/cert.pem" \
            --arg key "${CERT_DIR}/key.pem" \
            '
            {
                remark: (
                    .name //
                    .remark //
                    "railway-inbound"
                ),

                enable: (
                    if .enable == null
                    then true
                    else .enable
                    end
                ),

                expiryTime: (
                    .expiryTime //
                    0
                ),

                total: (
                    .total //
                    0
                ),

                listen: (
                    .listen //
                    ""
                ),

                port: .port,

                protocol: (
                    .protocol //
                    "vless"
                ),

                settings: (
                    .settings //
                    {}
                ),

                streamSettings: (
                    .streamSettings //
                    {}
                ),

                sniffing: (
                    .sniffing //
                    {
                        enabled: false,
                        destOverride: [
                            "http",
                            "tls",
                            "quic"
                        ]
                    }
                ),

                tag: (
                    .tag //
                    .name //
                    .remark //
                    "railway-inbound"
                )
            }

            |

            if (
                (.streamSettings.security? == "tls")
                and
                ($cert != "")
                and
                ($key != "")
                and
                (
                    (.streamSettings.tlsSettings.certificates? | type)
                    != "array"
                )
            )
            then

                .streamSettings.tlsSettings =
                    (
                        (.streamSettings.tlsSettings // {})
                        +
                        {
                            certificates: [
                                {
                                    certificateFile: $cert,
                                    keyFile: $key
                                }
                            ]
                        }
                    )

            else

                .

            end
            ' <<<"${SPEC}"
    )"

    if [[ -z "${BODY}" || "${BODY}" == "null" ]]; then

        echo "ERROR: failed to build request body."

        FAILED=$((FAILED + 1))

        continue

    fi

    echo "Request body prepared."

    # ========================================================
    # Add inbound
    # ========================================================

    RESPONSE_FILE="/tmp/xui-add-response.json"

    rm -f "${RESPONSE_FILE}"

    ADD_HTTP_CODE="$(
        curl \
            -sS \
            -o "${RESPONSE_FILE}" \
            -w "%{http_code}" \
            --connect-timeout 5 \
            --max-time 30 \
            "${

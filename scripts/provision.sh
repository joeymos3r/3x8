#!/usr/bin/env bash

set -u

DATA_DIR="${XUI_DATA_DIR:-/etc/x-ui}"
CONFIG="/opt/3x-ui/config/inbounds.json"

CERT_DIR="${XUI_CERT_DIR:-/root/cert/railway}"

COOKIE_JAR="${DATA_DIR}/.railway-xui-cookie"

PANEL_PORT="${XUI_PORT:-${PORT:-3000}}"

PANEL_BASE="${XUI_WEB_BASE_PATH:-/}"

BASE_URL="http://127.0.0.1:${PANEL_PORT}"

XUI_USER="${XUI_USERNAME:-admin}"
XUI_PASS="${XUI_PASSWORD:-admin}"

mkdir -p "${DATA_DIR}"
mkdir -p "${CERT_DIR}"

echo "=========================================="
echo " 3x-ui inbound provisioning"
echo " Panel: ${BASE_URL}"
echo "=========================================="

# --------------------------------------------------
# Check config
# --------------------------------------------------

if [[ ! -f "${CONFIG}" ]]; then

    echo "ERROR: Missing ${CONFIG}"

    exit 10

fi

if ! jq -e '.inbounds | type == "array"' "${CONFIG}" >/dev/null 2>&1; then

    echo "ERROR: Invalid inbounds.json"

    exit 11

fi

# --------------------------------------------------
# Generate certificate
# --------------------------------------------------

if [[ ! -s "${CERT_DIR}/cert.pem" || ! -s "${CERT_DIR}/key.pem" ]]; then

    echo "Generating self-signed TLS certificate..."

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

    chmod 600 "${CERT_DIR}/key.pem"

fi

# --------------------------------------------------
# Wait for panel
# --------------------------------------------------

echo "Waiting for panel..."

PANEL_READY=0

for i in $(seq 1 60); do

    HTTP_CODE="$(
        curl \
            -s \
            -o /dev/null \
            -w "%{http_code}" \
            --connect-timeout 2 \
            --max-time 3 \
            "${BASE_URL}/" \
            2>/dev/null
    )"

    if [[ "${HTTP_CODE}" != "000" ]]; then

        PANEL_READY=1

        echo "Panel responded with HTTP ${HTTP_CODE}"

        break

    fi

    sleep 2

done

if [[ "${PANEL_READY}" != "1" ]]; then

    echo "WARNING: panel is not responding."

    exit 20

fi

# --------------------------------------------------
# Login
# --------------------------------------------------

echo "Logging in to 3x-ui..."

rm -f "${COOKIE_JAR}"

LOGIN_BODY="$(
    jq -cn \
        --arg u "${XUI_USER}" \
        --arg p "${XUI_PASS}" \
        '{
            username: $u,
            password: $p
        }'
)"

LOGIN_HEADERS="/tmp/xui-login-headers.txt"
LOGIN_BODY_FILE="/tmp/xui-login-body.json"

rm -f "${LOGIN_HEADERS}"
rm -f "${LOGIN_BODY_FILE}"

LOGIN_HTTP_CODE="$(
    curl \
        -sS \
        -o "${LOGIN_BODY_FILE}" \
        -D "${LOGIN_HEADERS}" \
        -w "%{http_code}" \
        --max-time 15 \
        -c "${COOKIE_JAR}" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -X POST \
        "${BASE_URL}/login" \
        -d "${LOGIN_BODY}" \
        2>/dev/null
)"

LOGIN_RESP="$(cat "${LOGIN_BODY_FILE}" 2>/dev/null || true)"

echo "Login HTTP status: ${LOGIN_HTTP_CODE}"

if [[ "${LOGIN_HTTP_CODE}" == "403" ]]; then

    echo "=========================================="
    echo "WARNING: 3x-ui returned HTTP 403."
    echo ""
    echo "The panel itself is running."
    echo "The provisioning script will NOT crash."
    echo ""
    echo "Possible causes:"
    echo "1. XUI_USERNAME/XUI_PASSWORD do not match"
    echo "2. Existing Railway volume contains old credentials"
    echo "3. Panel security/CSRF rejected the request"
    echo "=========================================="

    rm -f "${COOKIE_JAR}"

    exit 30

fi

if [[ "${LOGIN_HTTP_CODE}" != "200" && "${LOGIN_HTTP_CODE}" != "204" ]]; then

    echo "WARNING: login failed with HTTP ${LOGIN_HTTP_CODE}"

    echo "Response:"
    echo "${LOGIN_RESP}"

    rm -f "${COOKIE_JAR}"

    exit 31

fi

if [[ -n "${LOGIN_RESP}" ]]; then

    LOGIN_SUCCESS="$(
        jq -r '.success // false' <<<"${LOGIN_RESP}" 2>/dev/null || echo "false"
    )"

    if [[ "${LOGIN_SUCCESS}" != "true" ]]; then

        echo "WARNING: 3x-ui login response indicates failure."

        echo "${LOGIN_RESP}"

        rm -f "${COOKIE_JAR}"

        exit 32

    fi

fi

echo "Login successful."

# --------------------------------------------------
# CSRF token
# --------------------------------------------------

echo "Obtaining CSRF token..."

CSRF_RESP="$(
    curl \
        -sS \
        --max-time 10 \
        -b "${COOKIE_JAR}" \
        -c "${COOKIE_JAR}" \
        -H "Accept: application/json" \
        "${BASE_URL}/panel/csrf-token" \
        2>/dev/null
)"

CSRF="$(
    jq -r '.obj // .token // empty' <<<"${CSRF_RESP}" 2>/dev/null || true
)"

# Some 3x-ui builds don't require an explicit token
# for the GET/list endpoint. Therefore don't abort here.

if [[ -n "${CSRF}" ]]; then

    echo "CSRF token received."

    AUTH_HEADERS=(
        -b "${COOKIE_JAR}"
        -H "X-CSRF-Token: ${CSRF}"
        -H "Content-Type: application/json"
        -H "Accept: application/json"
    )

else

    echo "WARNING: No explicit CSRF token returned."

    AUTH_HEADERS=(
        -b "${COOKIE_JAR}"
        -H "Content-Type: application/json"
        -H "Accept: application/json"
    )

fi

# --------------------------------------------------
# Read existing inbounds
# --------------------------------------------------

echo "Reading existing inbounds..."

EXISTING_FILE="/tmp/xui-existing-inbounds.json"

EXISTING_HTTP_CODE="$(
    curl \
        -sS \
        -o "${EXISTING_FILE}" \
        -w "%{http_code}" \
        --max-time 15 \
        -b "${COOKIE_JAR}" \
        -H "Accept: application/json" \
        "${BASE_URL}/panel/api/inbounds/list" \
        2>/dev/null
)"

EXISTING="$(cat "${EXISTING_FILE}" 2>/dev/null || true)"

echo "Inbound list HTTP status: ${EXISTING_HTTP_CODE}"

if [[ "${EXISTING_HTTP_CODE}" != "200" ]]; then

    echo "WARNING: Cannot read inbound list."

    echo "${EXISTING}"

    rm -f "${COOKIE_JAR}"

    exit 40

fi

EXISTING_SUCCESS="$(
    jq -r '.success // false' <<<"${EXISTING}" 2>/dev/null || echo "false"
)"

if [[ "${EXISTING_SUCCESS}" != "true" ]]; then

    echo "WARNING: 3x-ui rejected inbound list request."

    echo "${EXISTING}"

    rm -f "${COOKIE_JAR}"

    exit 41

fi

# --------------------------------------------------
# Create missing inbounds
# --------------------------------------------------

CREATED=0
SKIPPED=0
FAILED=0

while IFS= read -r SPEC; do

    NAME="$(jq -r '.name' <<<"${SPEC}")"

    PORT="$(jq -r '.port' <<<"${SPEC}")"

    PROTOCOL="$(jq -r '.protocol' <<<"${SPEC}")"

    echo ""
    echo "------------------------------------------"
    echo "Inbound: ${NAME}"
    echo "Protocol: ${PROTOCOL}"
    echo "Port: ${PORT}"
    echo "------------------------------------------"

    EXISTS="$(
        jq \
            -e \
            --arg name "${NAME}" \
            '.obj[]? | select(.remark == $name)' \
            <<<"${EXISTING}" \
            >/dev/null 2>&1
    )"

    if [[ "${EXISTS}" == "0" ]]; then

        echo "Inbound already exists."
        SKIPPED=$((SKIPPED + 1))

        continue

    fi

    BODY="$(
        jq -c \
            --arg cert "${CERT_DIR}/cert.pem" \
            --arg key "${CERT_DIR}/key.pem" '

            {
                remark: .name,

                enable: (.enable // false),

                expiryTime: 0,

                total: 0,

                listen: (.listen // ""),

                port: .port,

                protocol: .protocol,

                settings:
                    (.settings // {})
                    | tojson,

                streamSettings:
                    (
                        .streamSettings // {}
                    )
                    | (
                        if .security == "tls" then

                            .tlsSettings =
                                (
                                    (.tlsSettings // {})
                                    + {
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
                    )
                    | tojson,

                sniffing:
                    (
                        .sniffing
                        // {
                            enabled: false,
                            destOverride: [
                                "http",
                                "tls",
                                "quic"
                            ]
                        }
                    )
                    | tojson,

                tag:
                    (.tag // .name),

                trafficReset:
                    "never"
            }

        ' <<<"${SPEC}"
    )"

    RESPONSE_FILE="/tmp/xui-add-response.json"

    ADD_HTTP_CODE="$(
        curl \
            -sS \
            -o "${RESPONSE_FILE}" \
            -w "%{http_code}" \
            --max-time 20 \
            "${AUTH_HEADERS[@]}" \
            -X POST \
            "${BASE_URL}/panel/api/inbounds/add" \
            -d "${BODY}" \
            2>/dev/null
    )"

    RESPONSE="$(cat "${RESPONSE_FILE}" 2>/dev/null || true)"

    echo "Add HTTP status: ${ADD_HTTP_CODE}"

    if [[ "${ADD_HTTP_CODE}" != "200" ]]; then

        echo "WARNING: failed to create ${NAME}"

        echo "${RESPONSE}"

        FAILED=$((FAILED + 1))

        continue

    fi

    SUCCESS="$(
        jq -r '.success // false' <<<"${RESPONSE}" 2>/dev/null || echo "false"
    )"

    if [[ "${SUCCESS}" == "true" ]]; then

        echo "SUCCESS: Created ${NAME}"

        CREATED=$((CREATED + 1))

    else

        echo "WARNING: 3x-ui rejected ${NAME}"

        echo "${RESPONSE}"

        FAILED=$((FAILED + 1))

    fi

done < <(jq -c '.inbounds[]' "${CONFIG}")

# --------------------------------------------------
# Summary
# --------------------------------------------------

echo ""
echo "=========================================="
echo " Inbound provisioning finished"
echo " Created : ${CREATED}"
echo " Existing: ${SKIPPED}"
echo " Failed  : ${FAILED}"
echo "=========================================="

rm -f "${COOKIE_JAR}"

# NEVER crash 3x-ui because provisioning failed.
exit 0

#!/usr/bin/env bash

set -u

DATA_DIR="${XUI_DATA_DIR:-/etc/x-ui}"
CONFIG="/opt/3x-ui/config/inbounds.json"

CERT_DIR="${XUI_CERT_DIR:-/root/cert/railway}"

COOKIE_JAR="${DATA_DIR}/.railway-xui-cookie"

PANEL_PORT="${XUI_PORT:-${PORT:-3000}}"

BASE_URL="http://127.0.0.1:${PANEL_PORT}"

XUI_USER="${XUI_USERNAME:-admin}"
XUI_PASS="${XUI_PASSWORD:-admin}"

mkdir -p "${DATA_DIR}"
mkdir -p "${CERT_DIR}"

echo "=========================================="
echo " 3x-ui inbound provisioning"
echo " Panel: ${BASE_URL}"
echo " User: ${XUI_USER}"
echo "=========================================="

if [[ ! -f "${CONFIG}" ]]; then
    echo "ERROR: Missing ${CONFIG}"
    exit 10
fi

if ! jq -e '.inbounds | type == "array"' "${CONFIG}" >/dev/null 2>&1; then
    echo "ERROR: Invalid inbounds.json"
    exit 11
fi

INBOUND_COUNT="$(jq '.inbounds | length' "${CONFIG}")"

echo "Configured inbounds: ${INBOUND_COUNT}"

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

    chmod 600 "${CERT_DIR}/key.pem"

fi

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
            2>/dev/null || echo "000"
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

echo "Logging in to 3x-ui..."

rm -f "${COOKIE_JAR}"

LOGIN_HEADERS="/tmp/xui-login-headers.txt"
LOGIN_BODY_FILE="/tmp/xui-login-body.json"

rm -f "${LOGIN_HEADERS}"
rm -f "${LOGIN_BODY_FILE}"

# ==================================================
# LOGIN METHOD 1: JSON
# ==================================================

echo "Login attempt 1: JSON"

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
        -d "{\"username\":\"${XUI_USER}\",\"password\":\"${XUI_PASS}\"}" \
        2>/dev/null || echo "000"
)"

LOGIN_RESP="$(cat "${LOGIN_BODY_FILE}" 2>/dev/null || true)"

echo "Login HTTP status: ${LOGIN_HTTP_CODE}"
echo "Login response: ${LOGIN_RESP}"

LOGIN_SUCCESS="false"

if [[ -n "${LOGIN_RESP}" ]]; then

    LOGIN_SUCCESS="$(
        jq -r '.success // false' \
        <<<"${LOGIN_RESP}" \
        2>/dev/null || echo "false"
    )"

fi

# ==================================================
# LOGIN METHOD 2: FORM DATA
# ==================================================

if [[ "${LOGIN_SUCCESS}" != "true" ]]; then

    echo "Login attempt 2: form data"

    rm -f "${COOKIE_JAR}"
    rm -f "${LOGIN_BODY_FILE}"
    rm -f "${LOGIN_HEADERS}"

    LOGIN_HTTP_CODE="$(
        curl \
            -sS \
            -o "${LOGIN_BODY_FILE}" \
            -D "${LOGIN_HEADERS}" \
            -w "%{http_code}" \
            --max-time 15 \
            -c "${COOKIE_JAR}" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -H "Accept: application/json" \
            -X POST \
            "${BASE_URL}/login" \
            --data-urlencode "username=${XUI_USER}" \
            --data-urlencode "password=${XUI_PASS}" \
            2>/dev/null || echo "000"
    )"

    LOGIN_RESP="$(cat "${LOGIN_BODY_FILE}" 2>/dev/null || true)"

    echo "Login HTTP status: ${LOGIN_HTTP_CODE}"
    echo "Login response: ${LOGIN_RESP}"

    LOGIN_SUCCESS="$(
        jq -r '.success // false' \
        <<<"${LOGIN_RESP}" \
        2>/dev/null || echo "false"
    )"

fi

if [[ "${LOGIN_SUCCESS}" != "true" ]]; then

    echo "=========================================="
    echo "ERROR: 3x-ui login failed."
    echo "HTTP: ${LOGIN_HTTP_CODE}"
    echo "Response: ${LOGIN_RESP}"
    echo ""
    echo "XUI_USERNAME=${XUI_USER}"
    echo "Check XUI_PASSWORD."
    echo "If Railway has an existing volume,"
    echo "the database may contain different credentials."
    echo "=========================================="

    rm -f "${COOKIE_JAR}"

    exit 30

fi

echo "Login successful."

# ==================================================
# CSRF
# ==================================================

echo "Obtaining CSRF token..."

CSRF_RESP="$(
    curl \
        -sS \
        --max-time 10 \
        -b "${COOKIE_JAR}" \
        -c "${COOKIE_JAR}" \
        -H "Accept: application/json" \
        "${BASE_URL}/panel/csrf-token" \
        2>/dev/null || true
)"

CSRF="$(
    jq -r '.obj // .token // empty' \
    <<<"${CSRF_RESP}" \
    2>/dev/null || true
)"

if [[ -n "${CSRF}" ]]; then

    echo "CSRF token received."

    AUTH_HEADERS=(
        -b "${COOKIE_JAR}"
        -H "X-CSRF-Token: ${CSRF}"
        -H "Content-Type: application/json"
        -H "Accept: application/json"
    )

else

    echo "No explicit CSRF token."

    AUTH_HEADERS=(
        -b "${COOKIE_JAR}"
        -H "Content-Type: application/json"
        -H "Accept: application/json"
    )

fi

# ==================================================
# GET EXISTING INBOUNDS
# ==================================================

echo "Reading existing inbounds..."

EXISTING_FILE="/tmp/xui-existing-inbounds.json"

EXISTING_HTTP_CODE="$(
    curl \
        -sS \
        -o "${EXISTING_FILE}" \
        -w "%{http_code}" \
        --max-time 15 \
        "${AUTH_HEADERS[@]}" \
        "${BASE_URL}/panel/api/inbounds/list" \
        2>/dev/null || echo "000"
)"

EXISTING="$(cat "${EXISTING_FILE}" 2>/dev/null || true)"

echo "Inbound list HTTP status: ${EXISTING_HTTP_CODE}"

echo "Inbound list response: ${EXISTING}"

if [[ "${EXISTING_HTTP_CODE}" != "200" ]]; then

    echo "WARNING: Cannot read inbound list."

    rm -f "${COOKIE_JAR}"

    exit 40

fi

EXISTING_SUCCESS="$(
    jq -r '.success // false' \
    <<<"${EXISTING}" \
    2>/dev/null || echo "false"
)"

if [[ "${EXISTING_SUCCESS}" != "true" ]]; then

    echo "WARNING: 3x-ui rejected inbound list request."

    echo "${EXISTING}"

    rm -f "${COOKIE_JAR}"

    exit 41

fi

echo "Existing inbounds loaded."

# ==================================================
# CREATE INBOUNDS
# ==================================================

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

    EXISTING_ID="$(
        jq -r \
            --arg name "${NAME}" \
            '.obj[]? | select(.remark == $name) | .id' \
            <<<"${EXISTING}" \
            2>/dev/null \
            | head -n 1
    )"

    if [[ -n "${EXISTING_ID}" && "${EXISTING_ID}" != "null" ]]; then

        echo "Inbound already exists. ID=${EXISTING_ID}"

        SKIPPED=$((SKIPPED + 1))

        continue

    fi

    echo "Inbound does not exist. Creating..."

    BODY="$(
        jq -c \
            --arg cert "${CERT_DIR}/cert.pem" \
            --arg key "${CERT_DIR}/key.pem" '

            {
                remark: .name,

                enable: (.enable // true),

                expiryTime: (.expiryTime // 0),

                total: (.total // 0),

                listen: (.listen // ""),

                port: .port,

                protocol: .protocol,

                settings:
                    (.settings // {}),

                streamSettings:
                    (
                        .streamSettings // {}
                    )
                    |
                    (
                        if .security == "tls" then

                            .tlsSettings =
                            (
                                (.tlsSettings // {})
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
                    ),

                sniffing:
                    (
                        .sniffing
                        //
                        {
                            enabled: false,
                            destOverride: [
                                "http",
                                "tls",
                                "quic"
                            ]
                        }
                    ),

                tag:
                    (.tag // .name)
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
            2>/dev/null || echo "000"
    )"

    RESPONSE="$(cat "${RESPONSE_FILE}" 2>/dev/null || true)"

    echo "Add HTTP status: ${ADD_HTTP_CODE}"
    echo "Add response: ${RESPONSE}"

    if [[ "${ADD_HTTP_CODE}" != "200" ]]; then

        echo "WARNING: failed to create ${NAME}"

        FAILED=$((FAILED + 1))

        continue

    fi

    SUCCESS="$(
        jq -r '.success // false' \
        <<<"${RESPONSE}" \
        2>/dev/null || echo "false"
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

echo ""
echo "=========================================="
echo " Inbound provisioning finished"
echo " Created : ${CREATED}"
echo " Existing: ${SKIPPED}"
echo " Failed  : ${FAILED}"
echo "=========================================="

rm -f "${COOKIE_JAR}"

exit 0

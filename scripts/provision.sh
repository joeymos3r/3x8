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

for i in $(seq 1 120); do

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

    echo "Panel check ${i}/120 -> HTTP ${HTTP_CODE}"

    if [[ "${HTTP_CODE}" != "000" && -n "${HTTP_CODE}" ]]; then

        PANEL_READY=1

        echo "Panel is ready."

        break

    fi

    sleep 2

done

if [[ "${PANEL_READY}" != "1" ]]; then

    echo "ERROR: panel did not become ready."

    exit 20

fi

echo "Panel HTTP server is ready."
echo "Waiting 3 seconds for API initialization..."

sleep 3

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

LOGIN_BODY_FILE="/tmp/xui-login-body.json"

rm -f "${LOGIN_BODY_FILE}"

LOGIN_HTTP_CODE="$(
    curl \
        -sS \
        -o "${LOGIN_BODY_FILE}" \
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
echo "Login response: ${LOGIN_RESP}"

if [[ "${LOGIN_HTTP_CODE}" == "000" ]]; then

    echo "ERROR: Cannot connect to 3x-ui."

    exit 30

fi

if [[ "${LOGIN_HTTP_CODE}" == "403" ]]; then

    echo "ERROR: 3x-ui returned HTTP 403."
    echo "Username/password do not match the existing database."

    exit 31

fi

if [[ "${LOGIN_HTTP_CODE}" != "200" && "${LOGIN_HTTP_CODE}" != "204" ]]; then

    echo "ERROR: login failed."

    exit 32

fi

LOGIN_SUCCESS="$(
    jq -r '.success // false' <<<"${LOGIN_RESP}" 2>/dev/null || echo "false"
)"

if [[ "${LOGIN_SUCCESS}" != "true" ]]; then

    echo "ERROR: 3x-ui login response indicates failure."

    echo "${LOGIN_RESP}"

    exit 33

fi

echo "Login successful."

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

if [[ "${EXISTING_HTTP_CODE}" == "000" ]]; then

    echo "ERROR: Cannot connect to inbound API."

    exit 40

fi

if [[ "${EXISTING_HTTP_CODE}" != "200" ]]; then

    echo "ERROR: Cannot read inbound list."

    echo "${EXISTING}"

    exit 41

fi

EXISTING_SUCCESS="$(
    jq -r '.success // false' <<<"${EXISTING}" 2>/dev/null || echo "false"
)"

if [[ "${EXISTING_SUCCESS}" != "true" ]]; then

    echo "ERROR: 3x-ui rejected inbound list request."

    echo "${EXISTING}"

    exit 42

fi

CREATED=0
SKIPPED=0
FAILED=0

while IFS= read -r SPEC; do

    NAME="$(jq -r '.name' <<<"${SPEC}")"
    PORT="$(jq -r '.port' <<<"${SPEC}")"
    PROTOCOL="$(jq -r '.protocol' <<<"${SPEC}")"

    echo ""
    echo "=========================================="
    echo "Inbound: ${NAME}"
    echo "Protocol: ${PROTOCOL}"
    echo "Port: ${PORT}"
    echo "=========================================="

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

                enable: (.enable // true),

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
            -b "${COOKIE_JAR}" \
            -H "Content-Type: application/json" \
            -H "Accept: application/json" \
            -X POST \
            "${BASE_URL}/panel/api/inbounds/add" \
            -d "${BODY}" \
            2>/dev/null
    )"

    RESPONSE="$(cat "${RESPONSE_FILE}" 2>/dev/null || true)"

    echo "Add HTTP status: ${ADD_HTTP_CODE}"
    echo "Response: ${RESPONSE}"

    if [[ "${ADD_HTTP_CODE}" != "200" ]]; then

        echo "FAILED: ${NAME}"

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

        echo "FAILED: 3x-ui rejected ${NAME}"

        FAILED=$((FAILED + 1))

    fi

done < <(jq -c '.inbounds[]' "${CONFIG}")

echo ""
echo "=========================================="
echo " INBOUND PROVISIONING FINISHED"
echo " Created : ${CREATED}"
echo " Existing: ${SKIPPED}"
echo " Failed  : ${FAILED}"
echo "=========================================="

rm -f "${COOKIE_JAR}"

exit 0

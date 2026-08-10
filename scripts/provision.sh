#!/usr/bin/env bash
set -euo pipefail

DATA_DIR="${XUI_DATA_DIR:-/etc/x-ui}"
CONFIG="/opt/3x-ui/config/inbounds.json"
CERT_DIR="${XUI_CERT_DIR:-/root/cert/railway}"
COOKIE_JAR="${DATA_DIR}/.railway-xui-cookie"
LOCK_FILE="${DATA_DIR}/.railway-provision.lock"

XUI_USER="${XUI_USERNAME:-admin}"
XUI_PASS="${XUI_PASSWORD:-admin}"
PANEL_PORT="${XUI_PORT:-${PORT:-3000}}"
PANEL_BASE="${XUI_WEB_BASE_PATH:-/}"

mkdir -p "${DATA_DIR}" "${CERT_DIR}"

# Credentials are initialized by entrypoint.sh before the daemon starts.
# Keeping this script focused on API provisioning avoids changing credentials
# while the panel is already running.
# Generate a self-signed certificate so TLS inbounds are valid Xray configs.
# For real client use, replace it with a certificate for your public hostname.
if [[ ! -s "${CERT_DIR}/cert.pem" || ! -s "${CERT_DIR}/key.pem" ]]; then
    TLS_NAME="${XUI_TLS_SERVER_NAME:-localhost}"
    openssl req -x509 -nodes -newkey rsa:2048 -days "${XUI_TLS_CERT_DAYS:-3650}" \
      -keyout "${CERT_DIR}/key.pem" \
      -out "${CERT_DIR}/cert.pem" \
      -subj "/CN=${TLS_NAME}" >/dev/null 2>&1
    chmod 600 "${CERT_DIR}/key.pem"
fi

if [[ ! -f "${CONFIG}" ]]; then
    echo "Missing ${CONFIG}" >&2
    exit 1
fi

jq -e '.inbounds | type == "array" and length > 0' "${CONFIG}" >/dev/null

# Wait until the panel API is ready.
BASE_URL="http://127.0.0.1:${PANEL_PORT}"
for _ in $(seq 1 60); do
    if curl -fsS --max-time 3 "${BASE_URL}/" >/dev/null 2>&1; then
        break
    fi
    sleep 2
done

# Login and obtain a session cookie.  v3.x protects POST requests with CSRF.
rm -f "${COOKIE_JAR}"
LOGIN_BODY="$(jq -cn --arg u "${XUI_USER}" --arg p "${XUI_PASS}" '{username:$u,password:$p}')"
LOGIN_RESP="$(curl -fsS --max-time 10 -c "${COOKIE_JAR}" -H 'Content-Type: application/json' \
  -X POST "${BASE_URL}/login" -d "${LOGIN_BODY}")" || {
    echo "Could not log in to 3x-ui with XUI_USERNAME/XUI_PASSWORD." >&2
    echo "If this is an existing volume, leave those variables unchanged from the panel credentials." >&2
    exit 1
}

if [[ "$(jq -r '.success // false' <<<"${LOGIN_RESP}")" != "true" ]]; then
    echo "3x-ui login failed: $(jq -r '.msg // "unknown error"' <<<"${LOGIN_RESP}")" >&2
    exit 1
fi

CSRF_RESP="$(curl -fsS --max-time 10 -b "${COOKIE_JAR}" -c "${COOKIE_JAR}" "${BASE_URL}/panel/csrf-token")"
CSRF="$(jq -r '.obj // empty' <<<"${CSRF_RESP}")"
if [[ -z "${CSRF}" ]]; then
    echo "3x-ui did not return a CSRF token." >&2
    exit 1
fi

AUTH=(-b "${COOKIE_JAR}" -H "X-CSRF-Token: ${CSRF}" -H 'Content-Type: application/json')

EXISTING="$(curl -fsS --max-time 10 -b "${COOKIE_JAR}" "${BASE_URL}/panel/api/inbounds/list")"
if [[ "$(jq -r '.success // false' <<<"${EXISTING}")" != "true" ]]; then
    echo "Could not read the 3x-ui inbound list: $(jq -r '.msg // "unknown error"' <<<"${EXISTING}")" >&2
    exit 1
fi

# Add only missing remarks. This makes provisioning idempotent across restarts.
ADDED=0
SKIPPED=0
jq -c '.inbounds[]' "${CONFIG}" | while IFS= read -r spec; do
    NAME="$(jq -r '.name' <<<"${spec}")"
    if jq -e --arg name "${NAME}" '.obj[]? | select(.remark == $name)' <<<"${EXISTING}" >/dev/null 2>&1; then
        echo "Inbound already exists: ${NAME}"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    BODY="$(jq -c --arg cert "${CERT_DIR}/cert.pem" --arg key "${CERT_DIR}/key.pem" '
      .payload
      | .settings = (.settings // {})
      | .streamSettings = (.streamSettings // {})
      | if .streamSettings.security == "tls" then
          .streamSettings.tlsSettings = ((.streamSettings.tlsSettings // {}) + {
            certificates: [{certificateFile:$cert,keyFile:$key}]
          })
        else . end
      | {remark:.name, enable:(.enable // false), expiryTime:0, total:0,
         listen:(.listen // ""), port:.port, protocol:.protocol,
         settings:(.settings|tojson), streamSettings:(.streamSettings|tojson),
         sniffing:((.sniffing // {enabled:false, destOverride:["http","tls","quic"]})|tojson),
         tag:(.tag // .name), trafficReset:"never"}
    ' <<<"${spec}")"

    RESP="$(curl -fsS --max-time 15 "${AUTH[@]}" -X POST \
      "${BASE_URL}/panel/api/inbounds/add" -d "${BODY}")" || {
        echo "Failed to create inbound: ${NAME}" >&2
        exit 1
    }

    if [[ "$(jq -r '.success // false' <<<"${RESP}")" != "true" ]]; then
        echo "3x-ui rejected ${NAME}: $(jq -r '.msg // "unknown error"' <<<"${RESP}")" >&2
        exit 1
    fi
    echo "Created inbound: ${NAME}"
done

rm -f "${COOKIE_JAR}"
echo "Inbound provisioning completed."

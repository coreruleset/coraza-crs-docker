#!/bin/sh
set -e

# Create Coraza runtime directories
mkdir -p "${CORAZA_TMP_DIR:-/tmp/coraza}" \
         "${CORAZA_DATA_DIR:-/tmp/coraza/data}" \
         "${CORAZA_UPLOAD_DIR:-/tmp/coraza/upload}" \
         "${CORAZA_AUDIT_STORAGE_DIR:-/var/log/coraza/audit}"

# Generate self-signed certificate if none provided
if [ ! -f "${SSL_CERT_FILE}" ]; then
    echo "Generating self-signed TLS certificate..."
    cert_dir=$(dirname "${SSL_CERT_FILE}")
    mkdir -p "${cert_dir}"
    openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout "${SSL_CERT_KEY_FILE}" \
        -out "${SSL_CERT_FILE}" \
        -days 365 -subj "/CN=${SERVER_NAME:-localhost}" 2>/dev/null
fi

echo "Generating configuration files..."

defined_envs=$(printf '${%s} ' $(awk "END { for (name in ENVIRON) { print ( name ~ /${filter}/ ) ? name : \"\" } }" < /dev/null ))

# Coraza configuration
echo "  - Coraza configuration file"
if [ -f "/config/coraza/coraza.conf" ]; then
    echo "    - Using user-provided Coraza configuration from /config/coraza/coraza.conf"
    cp "/config/coraza/coraza.conf" "/opt/coraza/config/coraza.conf"
else
    echo "    - Generating from template /templates/coraza.conf"
    envsubst "${defined_envs}" < "/templates/coraza.conf" > "/opt/coraza/config/coraza.conf"
fi

# Coraza rules includes
echo "  - Coraza rules file"
if [ -f "/config/coraza/coraza-rules.conf" ]; then
    echo "    - Using user-provided rules file from /config/coraza/coraza-rules.conf"
    cp "/config/coraza/coraza-rules.conf" "/opt/coraza/config/coraza-rules.conf"
else
    echo "    - Generating from template /templates/coraza-rules.conf"
    cp "/templates/coraza-rules.conf" "/opt/coraza/config/coraza-rules.conf"
fi

# nginx configuration
echo "  - nginx configuration"
if [ -f "/config/nginx/nginx.conf" ]; then
    echo "    - Using user-provided nginx.conf from /config/nginx/nginx.conf"
    cp "/config/nginx/nginx.conf" "/etc/nginx/nginx.conf"
else
    echo "    - Generating from template /templates/nginx.conf"
    envsubst "${defined_envs}" < "/templates/nginx.conf" > "/etc/nginx/nginx.conf"
fi

# User config files
if [ -z "$(ls -A /opt/coraza/config.d 2>/dev/null)" ]; then
    echo "  - No user configuration files found in /opt/coraza/config.d"
else
    echo "  - User configuration files loaded from /opt/coraza/config.d"
    for f in /opt/coraza/config.d/*.conf; do
        echo "    -> $(basename "$f")"
    done
fi

if [ -z "$(ls -A /opt/coraza/rules.d 2>/dev/null)" ]; then
    echo "  - No user defined rule sets found in /opt/coraza/rules.d"
else
    echo "  - User defined rule sets loaded from /opt/coraza/rules.d"
    for f in /opt/coraza/rules.d/*.conf; do
        echo "    -> $(basename "$f")"
    done
fi

# Activate CRS rules
. /opt/coraza/activate-rules.sh

echo "Launching $*"
exec "$@"

#!/bin/sh

# Generate appropriate configuration files and launch Caddy
set -e

# Create Coraza runtime directories
mkdir -p "${CORAZA_TMP_DIR:-/tmp/coraza}" \
         "${CORAZA_DATA_DIR:-/tmp/coraza/data}" \
         "${CORAZA_UPLOAD_DIR:-/tmp/coraza/upload}" \
         "${CORAZA_AUDIT_STORAGE_DIR:-/var/log/coraza/audit}"

echo "Generating configuration files..."

# Map ERRORLOG to a Caddy log writer (the global log block in the Caddyfile).
# Caddy's file writer rolls the file at 100 MB by default and creates it with
# mode 0600, so:
# - /dev/stderr, /dev/stdout and /dev/null use Caddy's stderr, stdout and
#   discard writers.
# - Any other device or /proc path (e.g. /proc/self/fd/2) is written as a file
#   with rolling disabled: a device must never be renamed.
# - A regular file is created with mode 0644, like nginx and Apache error logs,
#   so tools reading it from a bind mount (e.g. go-ftw) can open it. Missing
#   parent directories get the matching mode (0755) instead of Caddy's 0700,
#   or the file would still be out of reach. With
#   CRS_ENABLE_TEST_MARKER=1 rolling is disabled too: a roll in the middle of a
#   go-ftw run hides every later log line from it.
# The path is quoted so that it may contain spaces.
ERRORLOG="${ERRORLOG:-/dev/stderr}"
case "${ERRORLOG}" in
  /dev/stderr) CADDY_ERRORLOG_OUTPUT="stderr" ;;
  /dev/stdout) CADDY_ERRORLOG_OUTPUT="stdout" ;;
  /dev/null) CADDY_ERRORLOG_OUTPUT="discard" ;;
  /dev/*|/proc/*)
    CADDY_ERRORLOG_OUTPUT="$(printf 'file "%s" {\n  roll_disabled\n}' "${ERRORLOG}")" ;;
  *)
    errorlog_roll=""
    if [ "${CRS_ENABLE_TEST_MARKER:-0}" = "1" ]; then
      errorlog_roll="roll_disabled"
    fi
    CADDY_ERRORLOG_OUTPUT="$(printf 'file "%s" {\n  mode 0644\n  dir_mode from_file\n  %s\n}' "${ERRORLOG}" "${errorlog_roll}")" ;;
esac
export ERRORLOG CADDY_ERRORLOG_OUTPUT

ERRORLOG_FORMAT="${ERRORLOG_FORMAT:-json}"
case "${ERRORLOG_FORMAT}" in
  json|console) ;;
  *)
    echo "ERRORLOG_FORMAT must be 'json' or 'console', got '${ERRORLOG_FORMAT}'" >&2
    exit 1 ;;
esac
export ERRORLOG_FORMAT

defined_envs=$(printf '${%s} ' $(awk "END { for (name in ENVIRON) { print ( name ~ /${filter}/ ) ? name : \"\" } }" < /dev/null ))

# Test if Caddyfile has been mounted in a volume by the user; if so that will be used rather than the default
echo "  - Caddyfile"
if [ -f "/config/caddy/Caddyfile" ]; then
  echo "    - Using user-provided Caddyfile from /config/caddy/Caddyfile"
  cp "/config/caddy/Caddyfile" "/etc/caddy/Caddyfile"
  echo "    - Done"
else
  echo "    - Generating Caddyfile from template /templates/Caddyfile"
  envsubst "${defined_envs}" < "/templates/Caddyfile" > "/etc/caddy/Caddyfile"
  caddy fmt --overwrite /etc/caddy/Caddyfile
  echo "    - Done"
fi

# Test if Coraza configuration file has been mounted in a volume by the user; if so that will b e used rather than the default
echo "  - Coraza configuration file"
if [ -f "/config/coraza/coraza.conf" ]; then
  echo "    - Using user-provided Coraza configuration file from /config/coraza/coraza.conf"
  cp "/config/coraza/coraza.conf" "/opt/coraza/config/coraza.conf"
  echo "    - Done"
else
  echo "    - Generating Caddyfile from template /templates/coraza.conf"
  envsubst "${defined_envs}" < "/templates/coraza.conf" > "/opt/coraza/config/coraza.conf"
  echo "    - Done"
fi

# Output the extra configuration files that will be read as hints to the user
if [ -z "$(ls -A /opt/coraza/config.d)" ]; then
  echo "  - No user configuration files found in /opt/coraza/config.d"
else
  echo "  - User configuration files loaded from /opt/coraza/config.d"
  for f in /opt/coraza/config.d/*.conf
  do
    echo "    -> $(basename $f)"
  done
  echo "    - Done"
fi

if [ -z "$(ls -A /opt/coraza/plugins)" ]; then
  echo "  - No user plugins found in /opt/coraza/plugins"
else
  echo "  - User plugins loaded from /opt/coraza/plugins"
  for f in /opt/coraza/plugins/*.conf
  do
    echo "    -> $(basename $f)"
  done
  echo "    - Done"
fi

if [ -z "$(ls -A /opt/coraza/rules.d)" ]; then
  echo "  - No user defined rule sets found in /opt/coraza/rules.d"
else
  echo "  - User defined rule sets loaded from /opt/coraza/rules.d"
  for f in /opt/coraza/rules.d/*.conf
  do
    echo "    -> $(basename $f)"
  done
  echo "    - Done"
fi

# Activating CRS rules
. /opt/coraza/activate-rules.sh

# Launch Caddy
echo "Launching $*"
exec "$@"

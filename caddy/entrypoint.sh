#!/bin/sh

# Generate appropriate configuration files and launch Caddy
set -e

# Create Coraza runtime directories
mkdir -p "${CORAZA_TMP_DIR:-/tmp/coraza}" \
         "${CORAZA_DATA_DIR:-/tmp/coraza/data}" \
         "${CORAZA_UPLOAD_DIR:-/tmp/coraza/upload}" \
         "${CORAZA_AUDIT_STORAGE_DIR:-/var/log/coraza/audit}"

echo "Generating configuration files..."

# log_output <variable> <path> <error|access>: print the Caddy log writer for a
# log path, the way nginx and Apache treat their log paths:
# - /dev/stderr, /dev/stdout and /dev/null use Caddy's stderr, stdout and
#   discard writers.
# - Anything that exists and isn't a regular file (a device, or the pipe that
#   /proc/self/fd/2 is under Docker) is written without rolling: it must never
#   be renamed.
# - error: a regular file is never rolled, like the nginx and Apache error
#   logs. A new one is created 0644 in 0755 directories, so a reader on the
#   host (e.g. go-ftw) can open it; an existing one keeps its owner and mode
#   (Caddy would chmod it, and can't for a file the host created).
# - access: a regular file keeps Caddy's defaults (0600, rolled at 100 MB), as
#   before.
# The path is quoted in the Caddyfile; characters Caddy would read as quoting,
# escapes or {$ENV} placeholders are refused.
log_output() {
  name="$1" path="$2" kind="$3"
  case "${path}" in
    *'"'*|*'\'*|*'{'*|*'}'*)
      echo "${name} must not contain \", \\, { or }: '${path}'" >&2
      exit 1 ;;
    /dev/stderr) echo "stderr"; return ;;
    /dev/stdout) echo "stdout"; return ;;
    /dev/null) echo "discard"; return ;;
  esac
  if [ -e "${path}" ] && [ ! -f "${path}" ]; then
    printf 'file "%s" {\n  roll_disabled\n}' "${path}"
  elif [ "${kind}" = "access" ]; then
    printf 'file "%s"' "${path}"
  elif [ -e "${path}" ]; then
    printf 'file "%s" {\n  roll_disabled\n}' "${path}"
  else
    printf 'file "%s" {\n  mode 0644\n  dir_mode from_file\n  roll_disabled\n}' "${path}"
  fi
}

defined_envs=$(printf '${%s} ' $(awk "END { for (name in ENVIRON) { print ( name ~ /${filter}/ ) ? name : \"\" } }" < /dev/null ))

# Test if Caddyfile has been mounted in a volume by the user; if so that will be used rather than the default
echo "  - Caddyfile"
if [ -f "/config/caddy/Caddyfile" ]; then
  echo "    - Using user-provided Caddyfile from /config/caddy/Caddyfile"
  cp "/config/caddy/Caddyfile" "/etc/caddy/Caddyfile"
  echo "    - Done"
else
  echo "    - Generating Caddyfile from template /templates/Caddyfile"
  # These only matter for the generated Caddyfile, so a mounted one is never
  # stopped by them.
  ERRORLOG_FORMAT="${ERRORLOG_FORMAT:-json}"
  case "${ERRORLOG_FORMAT}" in
    json|console) ;;
    *)
      echo "ERRORLOG_FORMAT must be 'json' or 'console', got '${ERRORLOG_FORMAT}'" >&2
      exit 1 ;;
  esac
  # log_output exits its subshell on a bad path; stop here with its message.
  CADDY_ERRORLOG_OUTPUT="$(log_output ERRORLOG "${ERRORLOG:-/dev/stderr}" error)" || exit 1
  CADDY_ACCESSLOG_OUTPUT="$(log_output ACCESSLOG "${ACCESSLOG:-/dev/stdout}" access)" || exit 1
  export ERRORLOG_FORMAT CADDY_ERRORLOG_OUTPUT CADDY_ACCESSLOG_OUTPUT
  caddy_envs=$(printf '${%s} ' $(awk "END { for (name in ENVIRON) { print ( name ~ /${filter}/ ) ? name : \"\" } }" < /dev/null ))
  envsubst "${caddy_envs}" < "/templates/Caddyfile" > "/etc/caddy/Caddyfile"
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

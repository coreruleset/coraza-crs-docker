#!/usr/bin/env bash
#
# Functional tests for the Coraza CRS Docker images.
#
# The tests start the image under test as a reverse proxy in front of a
# traefik/whoami backend and drive it with curl: legitimate traffic must be
# proxied through, attack traffic must be blocked by CRS, and the documented
# environment variables must actually change that behaviour.
#
# Usage:
#   tests/run-tests.sh [-v caddy|nginx|apache] [-i image] [-b]
#
#   -v  variant under test (default: caddy)
#   -i  image to test (default: coraza-crs-test:<variant>)
#   -b  build the image with docker buildx bake before testing
#
# Examples:
#   tests/run-tests.sh -v caddy -b
#   tests/run-tests.sh -v nginx -i ghcr.io/coreruleset/coraza-crs:nginx-latest

set -u -o pipefail

VARIANT="caddy"
IMAGE=""
BUILD=0
BACKEND_IMAGE="${BACKEND_IMAGE:-traefik/whoami}"
# Seconds to wait for a container to start serving.
STARTUP_TIMEOUT="${STARTUP_TIMEOUT:-60}"

# usage [exit-code] — print the header comment of this script as help text.
usage() {
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
  exit "${1:-0}"
}

while getopts ":v:i:bh" opt; do
  case "${opt}" in
    v) VARIANT="${OPTARG}" ;;
    i) IMAGE="${OPTARG}" ;;
    b) BUILD=1 ;;
    h) usage 0 ;;
    *) usage 1 ;;
  esac
done

# The CI matrix uses bake target names (caddy-alpine-latest, nginx-lts, ...);
# accept those as-is. A full target name is what -b builds, so nginx-lts builds
# the LTS image rather than the latest one; a bare family name builds -latest.
case "${VARIANT}" in
  *-latest|*-lts) BAKE_TARGET="${VARIANT}" ;;
  caddy*) BAKE_TARGET="caddy-alpine-latest" ;;
  nginx*) BAKE_TARGET="nginx-latest" ;;
  apache*) BAKE_TARGET="apache-latest" ;;
esac

# Everything else keys off the variant family.
case "${VARIANT}" in
  caddy*) VARIANT="caddy" ;;
  nginx*) VARIANT="nginx" ;;
  apache*) VARIANT="apache" ;;
  *) echo "Unknown variant: ${VARIANT}" >&2 ; usage 1 ;;
esac

IMAGE="${IMAGE:-coraza-crs-test:${VARIANT}}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"

# Unique suffix so concurrent runs (CI matrix on one runner) do not collide.
RUN_ID="$$"
NETWORK="coraza-test-net-${RUN_ID}"
BACKEND_NAME="coraza-test-whoami-${RUN_ID}"
TMP_DIR="$(mktemp -d)"
# Every container started by the run, removed by cleanup(). They are kept
# running until the end so their logs are still available if a later check
# fails.
CONTAINERS=()
# Set by start_waf.
WAF_NAME=""
WAF_ENDPOINT=""

TESTS_RUN=0
TESTS_FAILED=0

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

if [ -t 1 ]; then
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_BLUE=$'\033[34m'; C_OFF=$'\033[0m'
else
  C_RED=""; C_GREEN=""; C_BLUE=""; C_OFF=""
fi

# group <title> — start a new group of checks in the output.
group() {
  printf '\n%s==> %s%s\n' "${C_BLUE}" "$1" "${C_OFF}"
}

# pass <description> — record a successful check.
pass() {
  TESTS_RUN=$((TESTS_RUN + 1))
  printf '%s  ok%s   %s\n' "${C_GREEN}" "${C_OFF}" "$1"
}

# fail <description> [details] — record a failed check and keep going, so a
# run reports every problem instead of only the first one.
fail() {
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf '%s  FAIL%s %s\n' "${C_RED}" "${C_OFF}" "$1"
  [ $# -gt 1 ] && printf '       %s\n' "$2"
  return 0
}

# die <message> — abort the run; the EXIT trap still cleans up.
die() {
  printf '%sfatal:%s %s\n' "${C_RED}" "${C_OFF}" "$1" >&2
  exit 1
}

# cleanup — EXIT trap: dump container logs if the run failed, then remove
# every container, the network and the temporary directory it created.
cleanup() {
  local status=$?
  # On failure, dump the logs of every container we started: without them a red
  # CI run says nothing about why the WAF misbehaved.
  if [ "${TESTS_FAILED}" -ne 0 ] || [ "${status}" -ne 0 ]; then
    for c in "${CONTAINERS[@]:-}"; do
      [ -n "${c}" ] || continue
      printf '\n--- docker logs %s (last 50 lines) ---\n' "${c}"
      docker logs "${c}" 2>&1 | tail -50
    done
  fi
  for c in "${CONTAINERS[@]:-}"; do
    [ -n "${c}" ] && docker rm -f "${c}" >/dev/null 2>&1
  done
  docker rm -f "${BACKEND_NAME}" >/dev/null 2>&1
  docker network rm "${NETWORK}" >/dev/null 2>&1
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Container helpers
# ---------------------------------------------------------------------------

# start_waf <name-suffix> [env KEY=VALUE ...] [-- extra docker run args]
# Starts the image under test on an ephemeral host port and sets WAF_NAME to
# the container name and WAF_ENDPOINT to the host:port it is reachable on.
# It must not be called in a subshell: it registers the container in
# CONTAINERS so that cleanup() can dump its logs and remove it.
start_waf() {
  local suffix="$1"; shift
  local name="coraza-test-${suffix}-${RUN_ID}"
  local args=(--pull never -d --name "${name}" --network "${NETWORK}"
              -p 127.0.0.1::8080 -e "BACKEND=${BACKEND_NAME}:80")

  while [ $# -gt 0 ]; do
    case "$1" in
      --) shift; args+=("$@"); break ;;
      *) args+=(-e "$1"); shift ;;
    esac
  done

  docker run "${args[@]}" "${IMAGE}" >/dev/null || die "could not start ${name}"
  CONTAINERS+=("${name}")

  WAF_NAME="${name}"
  WAF_ENDPOINT="$(docker port "${name}" 8080/tcp | head -1)" \
    || die "could not read published port of ${name}"
}

# wait_for_http <host:port> — wait until the server proxies a request to the
# backend successfully. Answering at all is not enough: a WAF that is up before
# its backend replies 502, and starting a group there would fail assertions
# that have nothing wrong with them.
wait_for_http() {
  local endpoint="$1"
  local deadline=$((SECONDS + STARTUP_TIMEOUT))
  local code=""
  while [ "${SECONDS}" -lt "${deadline}" ]; do
    code="$(status "${endpoint}" "/")"
    [ "${code}" = "200" ] && return 0
    sleep 1
  done
  printf 'last response from %s: HTTP %s\n' "${endpoint}" "${code}" >&2
  return 1
}

# status <host:port> <path> [curl args...] — echo the HTTP status code.
status() {
  local endpoint="$1" path="$2"; shift 2
  curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$@" \
    "http://${endpoint}${path}" 2>/dev/null || echo "000"
}

# body <host:port> <path> [curl args...] — echo the response body.
body() {
  local endpoint="$1" path="$2"; shift 2
  curl -s --max-time 10 "$@" "http://${endpoint}${path}" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------

# assert_status <expected> <description> <host:port> <path> [curl args...]
assert_status() {
  local expected="$1" desc="$2"; shift 2
  local got
  got="$(status "$@")"
  if [ "${got}" = "${expected}" ]; then
    pass "${desc} (HTTP ${got})"
  else
    fail "${desc}" "expected HTTP ${expected}, got HTTP ${got}"
  fi
}

# assert_status_in <expected-list> <description> <host:port> <path> [curl args...]
assert_status_in() {
  local expected="$1" desc="$2"; shift 2
  local got
  got="$(status "$@")"
  case " ${expected} " in
    *" ${got} "*) pass "${desc} (HTTP ${got})" ;;
    *) fail "${desc}" "expected one of [${expected}], got HTTP ${got}" ;;
  esac
}

# assert_body_contains <needle> <description> <host:port> <path> [curl args...]
assert_body_contains() {
  local needle="$1" desc="$2"; shift 2
  local got
  got="$(body "$@")"
  if printf '%s' "${got}" | grep -qF -- "${needle}"; then
    pass "${desc}"
  else
    fail "${desc}" "response does not contain '${needle}': $(printf '%s' "${got}" | head -c 200)"
  fi
}

# assert_exec <container> <shell snippet> <description>
assert_exec() {
  local container="$1" snippet="$2" desc="$3"
  local out
  if out="$(docker exec "${container}" sh -c "${snippet}" 2>&1)"; then
    pass "${desc}"
  else
    fail "${desc}" "${out}"
  fi
}

# stream_logs <container> stdout|stderr — echo one output stream of a container.
stream_logs() {
  case "$2" in
    stdout) docker logs "$1" 2>/dev/null ;;
    stderr) docker logs "$1" 2>&1 >/dev/null ;;
  esac
}

# assert_stream <container> stdout|stderr present|absent <fixed string> <description>
# Logs can reach docker a moment after the response, so "present" retries for
# a few seconds and "absent" waits that long before concluding.
assert_stream() {
  local container="$1" stream="$2" want="$3" needle="$4" desc="$5"
  local out found=0 i
  for i in 1 2 3 4 5; do
    out="$(stream_logs "${container}" "${stream}")"
    if grep -qF -- "${needle}" <<<"${out}"; then found=1; else found=0; fi
    [ "${want}" = "present" ] && [ "${found}" -eq 1 ] && break
    sleep 1
  done
  if { [ "${want}" = "present" ] && [ "${found}" -eq 1 ]; } \
    || { [ "${want}" = "absent" ] && [ "${found}" -eq 0 ]; }; then
    pass "${desc}"
  else
    fail "${desc}" "expected '${needle}' to be ${want} on ${stream} of ${container}"
  fi
}

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

command -v docker >/dev/null || die "docker is required"
command -v curl >/dev/null || die "curl is required"

if [ "${BUILD}" -eq 1 ]; then
  group "Building ${IMAGE} (bake target ${BAKE_TARGET})"
  docker buildx bake -f "${REPO_DIR}/docker-bake.hcl" "${BAKE_TARGET}" \
    --set "*.platform=linux/$(docker version --format '{{.Server.Arch}}')" \
    --set "${BAKE_TARGET}.tags=${IMAGE}" \
    --load || die "build failed"
fi

docker image inspect "${IMAGE}" >/dev/null 2>&1 \
  || die "image ${IMAGE} not found locally; build it first (-b) or pass -i"

group "Starting backend (${BACKEND_IMAGE})"
docker network create "${NETWORK}" >/dev/null || die "could not create network"
docker run -d --name "${BACKEND_NAME}" --network "${NETWORK}" \
  "${BACKEND_IMAGE}" >/dev/null || die "could not start backend"
echo "  backend ${BACKEND_NAME} started on network ${NETWORK}"

# ---------------------------------------------------------------------------
# Default configuration: proxying, CRS blocking
# ---------------------------------------------------------------------------

group "Default configuration (${VARIANT}, CORAZA_RULE_ENGINE=On)"

start_waf main
MAIN_NAME="${WAF_NAME}"
MAIN="${WAF_ENDPOINT}"
wait_for_http "${MAIN}" || die "${MAIN_NAME} did not start serving within ${STARTUP_TIMEOUT}s"

if [ "$(docker inspect "${MAIN_NAME}" --format '{{.State.Running}}')" = "true" ]; then
  pass "container stays running"
else
  fail "container stays running"
fi

assert_status 200 "legitimate request is proxied" "${MAIN}" "/"
assert_body_contains "Hostname:" "response comes from the whoami backend" "${MAIN}" "/"
assert_status 200 "legitimate query string is allowed" \
  "${MAIN}" "/?search=coraza+crs+docker"
assert_status 200 "legitimate POST body is allowed" \
  "${MAIN}" "/" -X POST -d "name=john&city=paris"
assert_status 200 "legitimate JSON body is allowed" \
  "${MAIN}" "/" -X POST -H "Content-Type: application/json" \
  -d '{"name":"john","city":"paris"}'

assert_status 403 "XSS in query string is blocked" \
  "${MAIN}" "/?search=%3Cscript%3Ealert%281%29%3C%2Fscript%3E"
assert_status 403 "SQL injection in query string is blocked" \
  "${MAIN}" "/?id=1%27%20OR%20%271%27%3D%271"
assert_status 403 "path traversal is blocked" \
  "${MAIN}" "/?file=../../../../etc/passwd"
assert_status 403 "remote command execution attempt is blocked" \
  "${MAIN}" "/?cmd=%2Fbin%2Fcat%20%2Fetc%2Fpasswd"
assert_status 403 "known scanner user agent is blocked" \
  "${MAIN}" "/" -H "User-Agent: nikto"
assert_status 403 "SQL injection in POST body is blocked" \
  "${MAIN}" "/" -X POST -d "id=1' or '1'='1' -- "
assert_status 403 "XSS in JSON body is blocked" \
  "${MAIN}" "/" -X POST -H "Content-Type: application/json" \
  -d '{"comment":"<script>alert(1)</script>"}'
# nginx and Apache answer TRACE themselves (405) before CRS rule 911100
# gets a chance to deny it.
assert_status_in "403 405" "disallowed HTTP method is rejected" \
  "${MAIN}" "/" -X TRACE

# ---------------------------------------------------------------------------
# CORAZA_RULE_ENGINE
# ---------------------------------------------------------------------------

group "CORAZA_RULE_ENGINE=DetectionOnly"

start_waf detectiononly CORAZA_RULE_ENGINE=DetectionOnly
DETECT_NAME="${WAF_NAME}"
DETECT="${WAF_ENDPOINT}"
wait_for_http "${DETECT}" || die "${DETECT_NAME} did not start serving"
assert_status 200 "attack is detected but not blocked" \
  "${DETECT}" "/?search=%3Cscript%3Ealert%281%29%3C%2Fscript%3E"

group "CORAZA_RULE_ENGINE=Off"

start_waf engineoff CORAZA_RULE_ENGINE=Off
OFF_NAME="${WAF_NAME}"
OFF="${WAF_ENDPOINT}"
wait_for_http "${OFF}" || die "${OFF_NAME} did not start serving"
assert_status 200 "attack passes through with the engine disabled" \
  "${OFF}" "/?search=%3Cscript%3Ealert%281%29%3C%2Fscript%3E"
assert_status 200 "legitimate traffic still proxied with the engine disabled" \
  "${OFF}" "/"

# ---------------------------------------------------------------------------
# CRS tuning variables (activate-rules.sh)
# ---------------------------------------------------------------------------

group "CRS anomaly threshold (ANOMALY_INBOUND)"

start_waf anomaly ANOMALY_INBOUND=10000
ANOM_NAME="${WAF_NAME}"
ANOM="${WAF_ENDPOINT}"
wait_for_http "${ANOM}" || die "${ANOM_NAME} did not start serving"
assert_status 200 "attack stays under a very high inbound threshold" \
  "${ANOM}" "/?search=%3Cscript%3Ealert%281%29%3C%2Fscript%3E"

group "Custom rules from /opt/coraza/rules.d"

cat > "${TMP_DIR}/custom.conf" <<'RULE'
SecRule REQUEST_HEADERS:X-Test-Block "@streq blockme" \
    "id:100000,\
    phase:1,\
    deny,\
    status:403,\
    log,\
    msg:'custom test rule'"

# Phase 4 rule: only fires if the response body is actually buffered and
# inspected by the WAF module (see CORAZA_RESP_BODY_ACCESS).
SecRule REQUEST_HEADERS:X-Test-Response-Block "@streq blockme" \
    "id:100001,\
    phase:1,\
    pass,\
    nolog,\
    setvar:'tx.test_response_block=1'"

SecRule TX:test_response_block "@eq 1" \
    "id:100002,\
    phase:4,\
    chain,\
    deny,\
    status:403,\
    log,\
    msg:'custom test response rule'"
    SecRule RESPONSE_BODY "@contains Hostname" "t:none"
RULE
chmod 644 "${TMP_DIR}/custom.conf"

start_waf customrule \
  -- -v "${TMP_DIR}/custom.conf:/opt/coraza/rules.d/custom.conf:ro"
CUSTOM_NAME="${WAF_NAME}"
CUSTOM="${WAF_ENDPOINT}"
wait_for_http "${CUSTOM}" || die "${CUSTOM_NAME} did not start serving"
assert_status 403 "user rule from rules.d blocks the request" \
  "${CUSTOM}" "/" -H "X-Test-Block: blockme"
assert_status 200 "user rule does not affect other traffic" "${CUSTOM}" "/"
# Regression guard: coraza-caddy v1 never ran phase 4, so RESPONSE_BODY was
# always empty and every CRS RESPONSE-95x rule was inert.
assert_status 403 "response body is inspected in phase 4" \
  "${CUSTOM}" "/" -H "X-Test-Response-Block: blockme"

# ---------------------------------------------------------------------------
# Audit logging
# ---------------------------------------------------------------------------

group "Audit logging"

if [ "${VARIANT}" = "caddy" ]; then
  assert_exec "${MAIN_NAME}" \
    'test -d /var/log/coraza/audit && test -w /var/log/coraza/audit' \
    "default audit log directory exists and is writable"
  assert_exec "${MAIN_NAME}" 'test -d /var/log/caddy && test -w /var/log/caddy' \
    "default caddy log directory exists and is writable"
fi

start_waf audit \
  CORAZA_AUDIT_ENGINE=On \
  CORAZA_AUDIT_LOG=/var/log/coraza/audit/audit.log
AUDIT_NAME="${WAF_NAME}"
AUDIT="${WAF_ENDPOINT}"
wait_for_http "${AUDIT}" || die "${AUDIT_NAME} did not start serving"
curl -s -o /dev/null --max-time 10 \
  "http://${AUDIT}/?search=%3Cscript%3Ealert%281%29%3C%2Fscript%3E" || true
assert_exec "${AUDIT_NAME}" \
  'test -s /var/log/coraza/audit/audit.log' \
  "serial audit log file is written on attack"

start_waf concurrent-audit \
  CORAZA_AUDIT_ENGINE=On \
  CORAZA_AUDIT_LOG=/var/log/coraza/audit.log \
  CORAZA_AUDIT_LOG_TYPE=Concurrent \
  CORAZA_AUDIT_STORAGE_DIR=/var/log/coraza/audit
CONC_NAME="${WAF_NAME}"
CONC="${WAF_ENDPOINT}"
wait_for_http "${CONC}" || die "${CONC_NAME} did not start serving"
curl -s -o /dev/null --max-time 10 \
  "http://${CONC}/?search=%3Cscript%3Ealert%281%29%3C%2Fscript%3E" || true
assert_exec "${CONC_NAME}" \
  'find /var/log/coraza/audit -type f | grep -q .' \
  "concurrent audit log files are written on attack"

start_waf custom-audit-dir \
  CORAZA_AUDIT_STORAGE_DIR=/tmp/custom-audit-test
CUSTOMDIR_NAME="${WAF_NAME}"
CUSTOMDIR="${WAF_ENDPOINT}"
wait_for_http "${CUSTOMDIR}" || die "${CUSTOMDIR_NAME} did not start serving"
assert_exec "${CUSTOMDIR_NAME}" 'test -d /tmp/custom-audit-test' \
  "entrypoint creates a custom CORAZA_AUDIT_STORAGE_DIR"

# ---------------------------------------------------------------------------
# Error log and CRS test marker (what go-ftw needs)
# ---------------------------------------------------------------------------

ATTACK="/?search=%3Cscript%3Ealert%281%29%3C%2Fscript%3E"
WAF_JSON_LINE='"logger":"http.handlers.waf"'

group "CRS_ENABLE_TEST_MARKER"

# On Caddy, the marker container also uses the settings go-ftw needs. The log
# path contains a space on purpose: it must survive the generated Caddyfile.
if [ "${VARIANT}" = "caddy" ]; then
  FTW_LOG="/var/log/coraza/ftw logs/error.log"
  ACCESS_LOG="/var/log/caddy/access logs/access.log"
  start_waf testmarker \
    CRS_ENABLE_TEST_MARKER=1 \
    LOGLEVEL=info \
    "ERRORLOG=${FTW_LOG}" \
    ERRORLOG_FORMAT=console \
    "ACCESSLOG=${ACCESS_LOG}"
else
  start_waf testmarker CRS_ENABLE_TEST_MARKER=1
fi
MARKER_NAME="${WAF_NAME}"
MARKER="${WAF_ENDPOINT}"
wait_for_http "${MARKER}" || die "${MARKER_NAME} did not start serving"

# The generated rule must name the header in msg, and keep msg and ctl on
# separate lines (a single backslash in the heredoc used to join them).
SETUP_CONF="${TMP_DIR}/crs-setup.conf"
docker exec "${MARKER_NAME}" cat /opt/coraza/config/crs-setup.conf > "${SETUP_CONF}" 2>/dev/null
MARKER_MSG="$(grep -A1 -F "msg:'X-CRS-Test %{MATCHED_VAR}',\\" "${SETUP_CONF}")"
if grep -qx '    ctl:ruleRemoveById=1-999999"' <<<"${MARKER_MSG}"; then
  pass "marker rule names X-CRS-Test in msg, with ctl on its own line"
else
  fail "marker rule names X-CRS-Test in msg, with ctl on its own line" \
    "got: $(grep -A1 -F 'id:999999' "${SETUP_CONF}" | head -c 200)"
fi
assert_status 200 "request carrying the marker header is not blocked" \
  "${MARKER}" "${ATTACK}" -H "X-CRS-Test: marker-${RUN_ID}"

if [ "${VARIANT}" = "caddy" ]; then
  # go-ftw only accepts a marker line containing both "X-CRS-Test" and the
  # marker value, and matches plain-text [id "..."] fields.
  assert_exec "${MARKER_NAME}" \
    "grep -F 'X-CRS-Test marker-${RUN_ID}' '${FTW_LOG}' | grep -qF '[id \"999999\"]'" \
    "marker line is written in plain text to the ERRORLOG file"
  # NOTICE-severity matches are logged at info: 920330 (empty User-Agent,
  # paranoia level 1). curl sends an empty header for "User-Agent;".
  curl -s -o /dev/null --max-time 10 -H "User-Agent;" "http://${MARKER}/" || true
  assert_exec "${MARKER_NAME}" \
    "grep -qF '[id \"920330\"]' '${FTW_LOG}'" \
    "NOTICE-severity rule match is logged with LOGLEVEL=info"
  # Readable from a bind mount by another uid (go-ftw on the host); Caddy's
  # own default is 0600.
  assert_exec "${MARKER_NAME}" "test \"\$(stat -c %a '${FTW_LOG}')\" = 644" \
    "ERRORLOG file is created with mode 0644"
  assert_exec "${MARKER_NAME}" "test -s '${ACCESS_LOG}'" \
    "ACCESSLOG path with a space is written"
  # A roll at 100 MB in the middle of a go-ftw run would hide later lines.
  assert_exec "${MARKER_NAME}" "grep -q roll_disabled /etc/caddy/Caddyfile" \
    "ERRORLOG file is not rolled when CRS_ENABLE_TEST_MARKER=1"
fi

# ---------------------------------------------------------------------------
# ERRORLOG and ERRORLOG_FORMAT (Caddy maps them to its own log writers)
# ---------------------------------------------------------------------------

if [ "${VARIANT}" = "caddy" ]; then
  group "ERRORLOG / ERRORLOG_FORMAT (caddy)"

  # Default: the stderr writer, JSON. The default container has already
  # blocked attacks above.
  assert_exec "${MAIN_NAME}" "grep -qE '^[[:space:]]*output stderr$' /etc/caddy/Caddyfile" \
    "default ERRORLOG uses Caddy's stderr writer"
  assert_stream "${MAIN_NAME}" stderr present "${WAF_JSON_LINE}" \
    "default error log is JSON on stderr"
  assert_stream "${MAIN_NAME}" stdout absent "${WAF_JSON_LINE}" \
    "default error log is not on stdout"

  start_waf errorlog-stdout ERRORLOG=/dev/stdout
  STDOUT_NAME="${WAF_NAME}"
  wait_for_http "${WAF_ENDPOINT}" || die "${STDOUT_NAME} did not start serving"
  status "${WAF_ENDPOINT}" "${ATTACK}" >/dev/null
  assert_exec "${STDOUT_NAME}" "grep -qE '^[[:space:]]*output stdout$' /etc/caddy/Caddyfile" \
    "ERRORLOG=/dev/stdout uses Caddy's stdout writer"
  assert_stream "${STDOUT_NAME}" stdout present "${WAF_JSON_LINE}" \
    "ERRORLOG=/dev/stdout writes the error log to stdout"
  assert_stream "${STDOUT_NAME}" stderr absent "${WAF_JSON_LINE}" \
    "ERRORLOG=/dev/stdout writes nothing to stderr"

  start_waf errorlog-null ERRORLOG=/dev/null
  NULL_NAME="${WAF_NAME}"
  wait_for_http "${WAF_ENDPOINT}" || die "${NULL_NAME} did not start serving"
  status "${WAF_ENDPOINT}" "${ATTACK}" >/dev/null
  assert_exec "${NULL_NAME}" "grep -qE '^[[:space:]]*output discard$' /etc/caddy/Caddyfile" \
    "ERRORLOG=/dev/null uses Caddy's discard writer"
  assert_stream "${NULL_NAME}" stderr absent "${WAF_JSON_LINE}" \
    "ERRORLOG=/dev/null discards the error log"

  # Other device paths are written as files, but never rolled.
  start_waf errorlog-procfd ERRORLOG=/proc/self/fd/2
  PROCFD_NAME="${WAF_NAME}"
  wait_for_http "${WAF_ENDPOINT}" || die "${PROCFD_NAME} did not start serving"
  status "${WAF_ENDPOINT}" "${ATTACK}" >/dev/null
  assert_exec "${PROCFD_NAME}" \
    "grep -A1 -F 'output file \"/proc/self/fd/2\"' /etc/caddy/Caddyfile | grep -q roll_disabled" \
    "ERRORLOG=/proc/self/fd/2 is written without rolling"
  assert_stream "${PROCFD_NAME}" stderr present "${WAF_JSON_LINE}" \
    "ERRORLOG=/proc/self/fd/2 writes the error log to stderr"

  # An invalid format must fail at startup with a message naming the variable,
  # not with a Caddy module error.
  BADFMT_OUT="$(docker run --rm --pull never -e ERRORLOG_FORMAT=text "${IMAGE}" 2>&1)"
  BADFMT_STATUS=$?
  if [ "${BADFMT_STATUS}" -ne 0 ] && grep -qF "ERRORLOG_FORMAT must be 'json' or 'console'" <<<"${BADFMT_OUT}"; then
    pass "invalid ERRORLOG_FORMAT fails at startup with a clear message"
  else
    fail "invalid ERRORLOG_FORMAT fails at startup with a clear message" \
      "exit ${BADFMT_STATUS}: $(tail -2 <<<"${BADFMT_OUT}")"
  fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf '\n'
if [ "${TESTS_FAILED}" -eq 0 ]; then
  printf '%s%d/%d tests passed%s\n' "${C_GREEN}" "${TESTS_RUN}" "${TESTS_RUN}" "${C_OFF}"
  exit 0
fi
printf '%s%d of %d tests failed%s\n' "${C_RED}" "${TESTS_FAILED}" "${TESTS_RUN}" "${C_OFF}"
exit 1

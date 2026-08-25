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

usage() {
  sed -n '2,25p' "$0" | sed 's/^#\{1,2\} \{0,1\}//'
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
# accept those as-is and reduce them to the variant family.
case "${VARIANT}" in
  caddy*) VARIANT="caddy" ; BAKE_TARGET="caddy-alpine-latest" ;;
  nginx*) VARIANT="nginx" ; BAKE_TARGET="nginx-latest" ;;
  apache*) VARIANT="apache" ; BAKE_TARGET="apache-latest" ;;
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

group() {
  printf '\n%s==> %s%s\n' "${C_BLUE}" "$1" "${C_OFF}"
}

pass() {
  TESTS_RUN=$((TESTS_RUN + 1))
  printf '%s  ok%s   %s\n' "${C_GREEN}" "${C_OFF}" "$1"
}

fail() {
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf '%s  FAIL%s %s\n' "${C_RED}" "${C_OFF}" "$1"
  [ $# -gt 1 ] && printf '       %s\n' "$2"
  return 0
}

die() {
  printf '%sfatal:%s %s\n' "${C_RED}" "${C_OFF}" "$1" >&2
  exit 1
}

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

# wait_for_http <host:port> — wait until the server answers anything at all.
wait_for_http() {
  local endpoint="$1"
  local deadline=$((SECONDS + STARTUP_TIMEOUT))
  while [ "${SECONDS}" -lt "${deadline}" ]; do
    if curl -s -o /dev/null --max-time 2 "http://${endpoint}/"; then
      return 0
    fi
    sleep 1
  done
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
# Summary
# ---------------------------------------------------------------------------

printf '\n'
if [ "${TESTS_FAILED}" -eq 0 ]; then
  printf '%s%d/%d tests passed%s\n' "${C_GREEN}" "${TESTS_RUN}" "${TESTS_RUN}" "${C_OFF}"
  exit 0
fi
printf '%s%d of %d tests failed%s\n' "${C_RED}" "${TESTS_FAILED}" "${TESTS_RUN}" "${C_OFF}"
exit 1

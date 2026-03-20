ARG UBUNTU_VERSION="24.04"

# Build stage: download and prepare CRS
FROM ubuntu:${UBUNTU_VERSION} AS builder-crs

ARG CRS_VERSION="n/a"

RUN set -eux; \
    apt-get update -qq; \
    apt-get install -qq --no-install-recommends ca-certificates curl; \
    curl -fSL "https://github.com/coreruleset/coreruleset/archive/refs/tags/v${CRS_VERSION}.tar.gz" \
      -o /tmp/crs.tar.gz; \
    mkdir /var/tmp/owasp-crs; \
    tar x -z --strip-components=1 \
      -f /tmp/crs.tar.gz \
      -C /var/tmp/owasp-crs; \
    mkdir -p \
      /opt/coraza/config \
      /opt/coraza/rules \
      /opt/coraza/plugins \
      /opt/coraza/config.d \
      /opt/coraza/rules.d \
      /opt/coraza/overrides \
      /opt/coraza/owasp-crs; \
    cp -r /var/tmp/owasp-crs/rules /opt/coraza/owasp-crs; \
    cp -r /var/tmp/owasp-crs/plugins /opt/coraza/owasp-crs; \
    cp /var/tmp/owasp-crs/crs-setup.conf.example /opt/coraza/config/crs-setup.conf

# Runtime stage
FROM ubuntu:${UBUNTU_VERSION}

RUN set -eux; \
    apt-get update -qq; \
    apt-get install -qq --no-install-recommends \
      software-properties-common gettext-base; \
    add-apt-repository -y ppa:pierrepomes/libcoraza; \
    add-apt-repository -y ppa:pierrepomes/coraza-nginx; \
    apt-get update -qq; \
    apt-get install -qq --no-install-recommends \
      nginx libnginx-mod-http-coraza; \
    apt-get purge -y --auto-remove software-properties-common; \
    rm -rf /var/lib/apt/lists/*

# Copy CRS and directory structure from builder
COPY --from=builder-crs /opt/coraza /opt/coraza

# Copy shared templates and scripts
COPY src/templates/coraza.conf /templates/coraza.conf
COPY src/templates/coraza-rules.conf /templates/coraza-rules.conf
COPY src/templates/nginx.conf /templates/nginx.conf
COPY src/bin/activate-rules.sh /opt/coraza/activate-rules.sh

# Copy entrypoint
COPY nginx/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Create log and runtime directories (writable by nginx worker)
RUN set -eux; \
    mkdir -p /var/log/coraza /var/log/coraza/audit \
             /tmp/coraza /tmp/coraza/data /tmp/coraza/upload; \
    touch /var/log/coraza/audit.log; \
    chmod 777 /var/log/coraza /var/log/coraza/audit \
              /tmp/coraza /tmp/coraza/data /tmp/coraza/upload; \
    chmod 666 /var/log/coraza/audit.log

ENV \
    BACKEND=localhost:80 \
    CORAZA_ARGUMENTS_LIMIT=1000 \
    CORAZA_AUDIT_ENGINE="RelevantOnly" \
    CORAZA_AUDIT_LOG='/var/log/coraza/audit.log' \
    CORAZA_AUDIT_LOG_FORMAT=JSON \
    CORAZA_AUDIT_LOG_PARTS='ABIJDEFHZ' \
    CORAZA_AUDIT_LOG_RELEVANT_STATUS="^(?:5|4[0-9][0-35-9])" \
    CORAZA_AUDIT_LOG_TYPE='Serial' \
    CORAZA_AUDIT_STORAGE_DIR='/var/log/coraza/audit/' \
    CORAZA_DATA_DIR='/tmp/coraza/data' \
    CORAZA_DEBUG_LOG=/dev/null \
    CORAZA_DEBUG_LOGLEVEL=1 \
    CORAZA_DEFAULT_PHASE1_ACTION="phase:1,log,auditlog,pass" \
    CORAZA_DEFAULT_PHASE2_ACTION="phase:2,log,auditlog,pass" \
    CORAZA_REQ_BODY_ACCESS="On" \
    CORAZA_REQ_BODY_JSON_DEPTH_LIMIT=1024 \
    CORAZA_REQ_BODY_LIMIT=13107200 \
    CORAZA_REQ_BODY_LIMIT_ACTION="Reject" \
    CORAZA_REQ_BODY_NOFILES_LIMIT=524288 \
    CORAZA_RESP_BODY_ACCESS="On" \
    CORAZA_RESP_BODY_LIMIT=1048576 \
    CORAZA_RESP_BODY_LIMIT_ACTION="ProcessPartial" \
    CORAZA_RESP_BODY_MIMETYPE="text/plain text/html text/xml" \
    CORAZA_RULE_ENGINE=On \
    CORAZA_TAG=coraza \
    CORAZA_TMP_DIR=/tmp/coraza \
    CORAZA_TMP_SAVE_UPLOADED_FILES="on" \
    CORAZA_UPLOAD_DIR=/tmp/coraza/upload \
    CORAZA_UPLOAD_FILE_MODE=0600 \
    CORAZA_UPLOAD_KEEP_FILES="Off" \
    NGINX_LOGLEVEL=warn \
    PORT=80 \
    PARANOIA=1 \
    ANOMALY_INBOUND=5 \
    ANOMALY_OUTBOUND=4 \
    BLOCKING_PARANOIA=1

EXPOSE ${PORT}

ENTRYPOINT ["/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]

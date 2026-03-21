# syntax=docker/dockerfile:1

ARG NGINX_VERSION="1.28.2"

## Stage 1: Build libcoraza from source
FROM golang:1.25 AS go-builder

ARG LIBCORAZA_VERSION="n/a"

RUN set -eux; \
    apt-get update -qq; \
    apt-get install -qq --no-install-recommends \
        autoconf \
        automake \
        libtool \
        gcc \
        make \
        wget \
        ca-certificates

RUN set -eux; \
    wget -q "https://github.com/corazawaf/libcoraza/archive/refs/tags/${LIBCORAZA_VERSION}.tar.gz" \
      -O /tmp/libcoraza.tar.gz; \
    mkdir /tmp/libcoraza; \
    tar xzf /tmp/libcoraza.tar.gz --strip-components=1 -C /tmp/libcoraza; \
    cd /tmp/libcoraza; \
    ./build.sh; \
    ./configure; \
    make; \
    cp libcoraza.a /usr/local/lib/; \
    cp libcoraza.so /usr/local/lib/; \
    mkdir -p /usr/local/include/coraza; \
    cp coraza/coraza.h /usr/local/include/coraza/

## Stage 2: Build nginx module
FROM nginx:${NGINX_VERSION} AS nginx-builder

ARG CORAZA_NGINX_VERSION="n/a"

COPY --from=go-builder /usr/local/include/coraza /usr/local/include/coraza
COPY --from=go-builder /usr/local/lib/libcoraza.a /usr/local/lib/
COPY --from=go-builder /usr/local/lib/libcoraza.so /usr/local/lib/

RUN set -eux; \
    apt-get update -qq; \
    apt-get install -qq --no-install-recommends \
        gcc \
        libc-dev \
        make \
        libpcre2-dev \
        zlib1g-dev \
        libssl-dev \
        curl \
        ca-certificates

RUN set -eux; \
    curl -sSL "https://github.com/corazawaf/coraza-nginx/archive/refs/tags/v${CORAZA_NGINX_VERSION}.tar.gz" \
      -o /tmp/coraza-nginx.tar.gz; \
    mkdir /tmp/coraza-nginx; \
    tar xzf /tmp/coraza-nginx.tar.gz --strip-components=1 -C /tmp/coraza-nginx; \
    curl -sSL "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" \
      -o /tmp/nginx.tar.gz; \
    tar xzf /tmp/nginx.tar.gz -C /tmp; \
    cd /tmp/nginx-${NGINX_VERSION}; \
    ./configure --with-compat --add-dynamic-module=/tmp/coraza-nginx; \
    make modules; \
    strip objs/*.so; \
    cp objs/ngx_http_coraza_module.so /usr/lib/nginx/modules/

## Stage 3: Download CRS
FROM debian:bookworm-slim AS crs-release

ARG CRS_VERSION="n/a"

RUN set -eux; \
    apt-get update -qq; \
    apt-get install -qq --no-install-recommends ca-certificates curl; \
    curl -sSL "https://github.com/coreruleset/coreruleset/archive/refs/tags/v${CRS_VERSION}.tar.gz" \
      -o /tmp/crs.tar.gz; \
    mkdir /var/tmp/owasp-crs; \
    tar xzf /tmp/crs.tar.gz --strip-components=1 -C /var/tmp/owasp-crs; \
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

## Stage 4: Runtime (unprivileged image)
FROM nginxinc/nginx-unprivileged:${NGINX_VERSION}

USER root

COPY --from=go-builder /usr/local/lib/libcoraza.so /usr/local/lib/
COPY --from=nginx-builder /usr/lib/nginx/modules/ngx_http_coraza_module.so /usr/lib/nginx/modules/
COPY --from=crs-release /opt/coraza /opt/coraza

RUN set -eux; \
    apt-get update -qq; \
    apt-get install -qq --no-install-recommends gettext-base; \
    rm -rf /var/lib/apt/lists/*; \
    ldconfig

# Copy shared templates and scripts
COPY src/templates/coraza.conf /templates/coraza.conf
COPY src/templates/coraza-rules.conf /templates/coraza-rules.conf
COPY src/templates/nginx.conf /templates/nginx.conf
COPY src/bin/activate-rules.sh /opt/coraza/activate-rules.sh

# Copy entrypoint
COPY nginx/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Create log and runtime directories (owned by nginx user)
RUN set -eux; \
    mkdir -p /var/log/coraza /var/log/coraza/audit \
             /tmp/coraza /tmp/coraza/data /tmp/coraza/upload; \
    touch /var/log/coraza/audit.log; \
    chown -R nginx:nginx /var/log/coraza /tmp/coraza /opt/coraza /templates; \
    chmod 750 /var/log/coraza /var/log/coraza/audit \
              /tmp/coraza /tmp/coraza/data /tmp/coraza/upload; \
    chmod 640 /var/log/coraza/audit.log

USER nginx

ENV \
    BACKEND=localhost:80 \
    CORAZA_ARGUMENTS_LIMIT=1000 \
    CORAZA_AUDIT_ENGINE="RelevantOnly" \
    CORAZA_AUDIT_LOG='/dev/stdout' \
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
    PORT=8080 \
    PARANOIA=1 \
    ANOMALY_INBOUND=5 \
    ANOMALY_OUTBOUND=4 \
    BLOCKING_PARANOIA=1

EXPOSE ${PORT}

ENTRYPOINT ["/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]

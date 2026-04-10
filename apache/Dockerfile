# syntax=docker/dockerfile:1

ARG HTTPD_VERSION="2.4"
ARG GOLANG_VERSION="1.25"

## Stage 1: Build libcoraza from source
FROM golang:${GOLANG_VERSION} AS go-builder

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

## Stage 2: Build Apache module
FROM httpd:${HTTPD_VERSION} AS apache-builder

ARG CORAZA_APACHE_VERSION="n/a"

COPY --from=go-builder /usr/local/include/coraza /usr/local/include/coraza
COPY --from=go-builder /usr/local/lib/libcoraza.a /usr/local/lib/
COPY --from=go-builder /usr/local/lib/libcoraza.so /usr/local/lib/

RUN set -eux; \
    apt-get update -qq; \
    apt-get install -qq --no-install-recommends \
        gcc \
        libc-dev \
        make \
        libapr1-dev \
        libaprutil1-dev \
        apache2-dev \
        curl \
        ca-certificates

RUN set -eux; \
    curl -sSL "https://github.com/corazawaf/coraza-apache/archive/refs/tags/v${CORAZA_APACHE_VERSION}.tar.gz" \
      -o /tmp/coraza-apache.tar.gz; \
    mkdir /tmp/coraza-apache; \
    tar xzf /tmp/coraza-apache.tar.gz --strip-components=1 -C /tmp/coraza-apache; \
    cd /tmp/coraza-apache; \
    make; \
    strip src/.libs/mod_coraza.so; \
    cp src/.libs/mod_coraza.so /usr/local/apache2/modules/

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

## Stage 4: Runtime
FROM httpd:${HTTPD_VERSION}

COPY --from=go-builder /usr/local/lib/libcoraza.so /usr/local/lib/
COPY --from=apache-builder /usr/local/apache2/modules/mod_coraza.so /usr/local/apache2/modules/
COPY --from=crs-release /opt/coraza /opt/coraza

RUN set -eux; \
    apt-get update -qq; \
    apt-get install -qq --no-install-recommends gettext-base openssl; \
    rm -rf /var/lib/apt/lists/*; \
    ldconfig; \
    # Enable required modules and make ports configurable
    sed -i \
      -e 's/^#LoadModule proxy_module/LoadModule proxy_module/' \
      -e 's/^#LoadModule proxy_http_module/LoadModule proxy_http_module/' \
      -e 's/^#LoadModule ssl_module/LoadModule ssl_module/' \
      -e 's/^#LoadModule socache_shmcb_module/LoadModule socache_shmcb_module/' \
      -e 's/^#LoadModule headers_module/LoadModule headers_module/' \
      -e 's/^#LoadModule remoteip_module/LoadModule remoteip_module/' \
      -e 's/^#LoadModule rewrite_module/LoadModule rewrite_module/' \
      -e 's/^#LoadModule http2_module/LoadModule http2_module/' \
      -e 's|Listen 80|Listen ${PORT}\nListen ${SSL_PORT}|' \
      /usr/local/apache2/conf/httpd.conf; \
    # Make worker limits configurable via env var
    sed -i -E 's|(MaxRequestWorkers[ ]+)[0-9]+|\1${WORKER_CONNECTIONS}|' \
      /usr/local/apache2/conf/extra/httpd-mpm.conf

# Copy shared templates and scripts
COPY src/templates/coraza.conf /templates/coraza.conf
COPY src/templates/coraza-rules.conf /templates/coraza-rules.conf
COPY src/templates/apache-vhost.conf /templates/apache-vhost.conf
COPY src/bin/activate-rules.sh /opt/coraza/activate-rules.sh

# Copy entrypoint
COPY apache/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Create log and runtime directories (owned by apache worker user)
RUN set -eux; \
    mkdir -p /var/log/coraza /var/log/coraza/audit \
             /tmp/coraza /tmp/coraza/data /tmp/coraza/upload; \
    touch /var/log/coraza/audit.log; \
    chown -R www-data:www-data /var/log/coraza /tmp/coraza; \
    chmod 750 /var/log/coraza /var/log/coraza/audit \
              /tmp/coraza /tmp/coraza/data /tmp/coraza/upload; \
    chmod 640 /var/log/coraza/audit.log

# Set working directory to CRS rules for relative @pmFromFile paths
WORKDIR /opt/coraza/owasp-crs/rules

ENV \
    ACCESSLOG=/dev/stdout \
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
    ALWAYS_TLS_REDIRECT=off \
    ERRORLOG=/dev/stderr \
    H2_PROTOCOLS="h2 h2c http/1.1" \
    KEEPALIVE_TIMEOUT=60 \
    LOGLEVEL=warn \
    PORT=8080 \
    PROXY_TIMEOUT=60 \
    REMOTEIP_HEADER="X-Forwarded-For" \
    REMOTEIP_INT_PROXY="10.1.0.0/16" \
    SERVER_NAME=localhost \
    SERVER_TOKENS=Prod \
    SSL_CERT_FILE=/usr/local/apache2/conf/server.crt \
    SSL_CERT_KEY_FILE=/usr/local/apache2/conf/server.key \
    SSL_CIPHERS="ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384" \
    SSL_PORT=8443 \
    SSL_PROTOCOLS="all -SSLv3 -TLSv1 -TLSv1.1" \
    WORKER_CONNECTIONS=1024 \
    PARANOIA=1 \
    ANOMALY_INBOUND=5 \
    ANOMALY_OUTBOUND=4 \
    BLOCKING_PARANOIA=1

EXPOSE ${PORT}

ENTRYPOINT ["/entrypoint.sh"]
CMD ["httpd-foreground"]

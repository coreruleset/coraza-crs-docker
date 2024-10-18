# Set Caddy release tag
ARG CADDY_VERSION="n/a"

# Use official Caddy builder image
FROM caddy:"${CADDY_VERSION}-builder" AS builder-caddy

# Build Caddy with Coraza
RUN --mount=type=cache,target=/go,id=caddy \
  xcaddy build --with github.com/corazawaf/coraza-caddy

# Use official caddy builder image to get Core Rule Set
FROM caddy:"${CADDY_VERSION}-builder" AS builder-crs

# Set OWASP ModSecurity core rule set release tag to check out
# Available tags are on the GitHub releases page here: https://github.com/coreruleset/coreruleset/tags
ARG CRS_VERSION="n/a"

# Get OWASP ModSecurity Core Rule Set and main configuration file
# Ideally we can get back this cache: --mount=type=cache,target=/var/tmp,id=crs \
# But it seems that the cache is not working as expected on multi arch builds
RUN set -eux; \
  # Only retrieve and extract rule set if not existing due to cache layer
  if [ ! -d "/var/tmp/owasp-crs" ]; \
  then \
    # Get rule set archive
    wget -q -O "/var/tmp/crs-${CRS_VERSION}.tar.gz" "https://github.com/coreruleset/coreruleset/archive/refs/tags/v${CRS_VERSION}.tar.gz"; \
    # Extract rule set
    mkdir /var/tmp/owasp-crs; \
    tar x -z \
      --strip-components=1 \
      -f "/var/tmp/crs-${CRS_VERSION}.tar.gz" \
      -C /var/tmp/owasp-crs \
    ; \
  fi; \
  # Create directory structure for Coraza
  mkdir -p \
    # Main configuration directory
    /opt/coraza/config \
    # Main rules directory
    /opt/coraza/rules \
    # Plugins directory
    /opt/coraza/plugins \
    # User configuration directory
    /opt/coraza/config.d \
    # User rule directory
    /opt/coraza/rules.d \
    # Rule/configuration overrides
    /opt/coraza/overrides \
    # CRS rules directory
    /opt/coraza/owasp-crs \
  ; \
  # Copy rule set into rules dir
  cp -r /var/tmp/owasp-crs/rules /opt/coraza/owasp-crs; \
  # Copy plugins directory
  cp -r /var/tmp/owasp-crs/plugins /opt/coraza/owasp-crs; \
  # Copy CRS setup file into config dir
  cp /var/tmp/owasp-crs/crs-setup.conf.example /opt/coraza/config/crs-setup.conf

# Switch to official Caddy container
FROM caddy:"$CADDY_VERSION"

# Add libcap to allow Caddy to bind to port 80/443 with a low privledged account
# If this is not required it may be disabled (eg. if Caddy is listening on a high port)
ARG LIBCAP=true

# Set user and group IDs for user that will run Caddy
ARG CADDY_UID=1000
ARG CADDY_GID=1000

# Set user name and group name for the user that will run Caddy
ARG CADDY_USER=caddy
ARG CADDY_GROUP=caddy

# Set configuration directory
ARG CADDY_CONFIG_DIR=/config

# Set data directory
ARG CADDY_DATA_DIR=/data

# Copy newly built Caddy binary from builder-caddy
COPY --from=builder-caddy /usr/bin/caddy /usr/bin/caddy

# Copy out Coraza configuration files and rules from builder-caddy
COPY --from=builder-crs /opt/coraza /opt/coraza

# Copy rules activation script
COPY src/bin/activate-rules.sh /opt/coraza/activate-rules.sh

# Add user to run Caddy so it is not running as root
# This should only be done if the Caddy user/group is not set to root
# hadolint ignore=DL3018,SC1075
RUN set -eux; \
  # Test if Caddy user is root; if so these steps are not required
  if [ "$CADDY_USER" = "root" ]; \
  then \
    echo "Skipping Caddy user/group configuration; container will run Caddy as root"; \
  else \
    # Add Caddy group
    addgroup -g "$CADDY_GID" -S "$CADDY_GROUP"; \
    # Add Caddy user
    adduser -u "$CADDY_UID" -D -S -G "$CADDY_GROUP" "$CADDY_USER"; \
    # Fix permissions for configuration directories
    chown -R "$CADDY_UID":"$CADDY_GID" \
      "${CADDY_CONFIG_DIR}" \
      "${CADDY_DATA_DIR}" \
      "/opt/coraza" \
      "/etc/caddy" \
    ; \
  fi

# Set capability on Caddy binary if required to allow binding on low ports for unprivileged user
RUN set -eux; \
  # Test if libcap needs to be installed
  if [ "$LIBCAP" = true ]; \
  then \
    if [ "$CADDY_USER" != "root" ]; \
    then \
      # Install libcap
      apk add --no-cache libcap; \
      # Set capability on Caddy binary
      setcap cap_net_bind_service=ep /usr/bin/caddy; \
      # Remove libcap
      apk del libcap; \
    else \
      echo "Skipping libcap installation and setting of cap_net_bind_service capability for Caddy; running as root"; \
    fi; \
  else \
    echo "Skipping libcap installation and cap_net_bind_service capability for Caddy"; \
  fi

# Use envsubst instead of esh
RUN apk add --no-cache envsubst sed

# Add configuration templates
COPY src/templates /templates

# Add entrypoint script
COPY caddy/entrypoint.sh /entrypoint.sh

# Switch user
USER "${CADDY_USER}:${CADDY_GROUP}"

# Set env variables for config/data directories
ENV \
    ACCESSLOG=/var/log/caddy/access.log \
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
    CORAZA_DEFAULT_PHASE1_ACTION="phase:1,pass,log,tag:'\${CORAZA_TAG}'" \
    CORAZA_DEFAULT_PHASE2_ACTION="phase:2,pass,log,tag:'\${CORAZA_TAG}'" \
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
    PORT=8080 \
    XDG_CONFIG_HOME="$CADDY_CONFIG_DIR" \
    XDG_DATA_HOME="$CADDY_DATA_DIR" \
    # CRS specific variables
    PARANOIA=1 \
    ANOMALY_INBOUND=5 \
    ANOMALY_OUTBOUND=4 \
    BLOCKING_PARANOIA=1

# Create default volumes
VOLUME "$CADDY_CONFIG_DIR" "$CADDY_DATA_DIR"

# Set entrypoint
ENTRYPOINT ["/entrypoint.sh"]
CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]

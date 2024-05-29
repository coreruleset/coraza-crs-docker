# Set Caddy release tag
ARG CADDY_TAG="2.6.2"

# Use official Caddy builder image
FROM caddy:"${CADDY_TAG}-builder" as builder-caddy

# Build Caddy with Coraza
RUN --mount=type=cache,target=/go,id=caddy \
  xcaddy build --with github.com/corazawaf/coraza-caddy

# Use official caddy builder image to get Core Rule Set
FROM caddy:"${CADDY_TAG}-builder" as builder-crs

# Set OWASP ModSecurity core rule set release tag to check out
# Available tags are on the GitHub releases page here: https://github.com/coreruleset/coreruleset/tags
ARG CRS_TAG="v4.3.0"

# Get OWASP ModSecurity Core Rule Set and main configuration file
RUN --mount=type=cache,target=/var/tmp,id=crs \
  set -eux; \
  # Only retrieve and extract rule set if not existing due to cache layer
  if [ ! -d "/var/tmp/owasp-crs" ]; \
  then \
    # Get rule set archive
    wget -q -O "/var/tmp/crs-${CRS_TAG}.tar.gz" "https://github.com/coreruleset/coreruleset/archive/refs/tags/${CRS_TAG}.tar.gz"; \
    # Extract rule set
    mkdir /var/tmp/owasp-crs; \
    tar x -z \
      --strip-components=1 \
      -f "/var/tmp/crs-${CRS_TAG}.tar.gz" \
      -C /var/tmp/owasp-crs \
    ; \
  fi; \
  # Create directory structure for Coraza
  mkdir -p \
    # Main configuration directory
    /opt/coraza/config \
    # Additional rules directory (not used yet)
    /opt/coraza/rules \
    # User configuration directory
    /opt/coraza/config.d \
    # User rule directory
    /opt/coraza/rules.d \
    # Rule/configuration overrides
    /opt/coraza/overrides \
  ; \
  # Copy rule set into rules dir
  cp -r /var/tmp/owasp-crs/rules /opt/coraza/owasp-crs; \
  # Copy CRS setup file into config dir
  cp /var/tmp/owasp-crs/crs-setup.conf.example /opt/coraza/config/crs-setup.conf

# Use Caddy image to retrieve esh
FROM caddy:"${CADDY_TAG}-builder" as builder-esh

# Get esh and set permissions
RUN set -eux; \
  wget -q -O /usr/local/bin/esh "https://raw.githubusercontent.com/jirutka/esh/master/esh"; \
  chmod +x /usr/local/bin/esh

# Switch to official Caddy container
FROM caddy:"$CADDY_TAG"

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

# Copy our confd from build-confd
COPY --from=builder-esh /usr/local/bin/esh /usr/local/bin/esh

# Add configuration templates
COPY ./templates /templates

# Add entrypoint script
COPY ./entrypoint.sh /entrypoint.sh

# Switch user
USER "${CADDY_USER}:${CADDY_GROUP}"

# Set env variables for config/data directories
ENV XDG_CONFIG_HOME="$CADDY_CONFIG_DIR" XDG_DATA_HOME="$CADDY_DATA_DIR"

# Create default volumes
VOLUME "$CADDY_CONFIG_DIR" "$CADDY_DATA_DIR"

# Set entrypoint
ENTRYPOINT ["/entrypoint.sh"]
CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]

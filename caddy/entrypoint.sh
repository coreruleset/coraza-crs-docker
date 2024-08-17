#!/bin/sh

# Generate appropriate configuration files and launch Caddy
set -e
echo "Generating configuration files..."

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

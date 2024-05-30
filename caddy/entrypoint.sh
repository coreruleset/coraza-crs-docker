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

# Launch Caddy
echo "Launching $*"
exec "$@"

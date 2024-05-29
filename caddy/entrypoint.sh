#!/bin/sh

# Generate appropriate configuration files and launch Caddy
set -e
echo "Generating configuration files..."

# Test if Caddyfile has been mounted in a volume by the user; if so that will be used rather than the default
echo "  - Caddyfile"
if [ -f "/config/caddy/Caddyfile" ]; then
  echo "    - Using user-provided Caddyfile from /config/caddy/Caddyfile"
  cp "/config/caddy/Caddyfile" "/etc/caddy/Caddyfile"
  echo "    - Done"
else
  echo "    - Generating Caddyfile from template /templates/Caddyfile.esh"
  esh -o "/etc/caddy/Caddyfile" "/templates/Caddyfile.esh"
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
  echo "    - Generating Caddyfile from template /templates/coraza.conf.esh"
  esh -o "/opt/coraza/config/coraza.conf" "/templates/coraza.conf.esh"
  echo "    - Done"
fi

# Add any rule overrides if required
echo "  - Core rule set overrides"
echo "    - Generating core rule set overrides from template /templates/crs_disable.conf.esh"
esh -o "/opt/coraza/overrides/crs_disable.conf" "/templates/crs_disable.conf.esh"
echo "    - Done"

# Launch Caddy
echo "Launching $*"
exec "$@"
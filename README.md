# Coraza CRS Docker

Docker containers running [OWASP Coraza WAF](https://coraza.io/) with the [OWASP Core Rule Set (CRS)](https://github.com/coreruleset/coreruleset).

Three web server variants are available:

| Variant | Base | Image Tag |
| ------- | ---- | --------- |
| [Caddy](https://caddyserver.com/) | Alpine | `caddy-alpine` |
| [nginx](https://nginx.org/) | Ubuntu 24.04 | `nginx-ubuntu` |
| [Apache](https://httpd.apache.org/) | Ubuntu 24.04 | `apache-ubuntu` |

The containers act as a reverse proxy, inspecting traffic with Coraza WAF and CRS before forwarding to a backend service.

- [Coraza CRS Docker](#coraza-crs-docker)
  - [Quick Start](#quick-start)
  - [Env Variables](#env-variables)
    - [Coraza Specific](#coraza-specific)
    - [CRS Specific](#crs-specific)
    - [Web Server Specific](#web-server-specific)
  - [Configuration Files/Directories](#configuration-filesdirectories)
  - [Build Arguments](#build-arguments)
  - [Building](#building)
  - [Advanced Configuration](#advanced-configuration)

## Quick Start

Using docker compose:

```bash
# Caddy (default, port 8080)
docker compose up

# nginx (port 8081)
docker compose --profile nginx up

# Apache (port 8082)
docker compose --profile apache up

# All three
docker compose --profile all up
```

Or run directly:

```bash
# nginx
docker run -d -p 80:80 -e BACKEND=myapp:8080 ghcr.io/coreruleset/coraza-crs:nginx-ubuntu

# Apache
docker run -d -p 80:80 -e BACKEND=myapp:8080 ghcr.io/coreruleset/coraza-crs:apache-ubuntu

# Caddy
docker run -d -p 8080:8080 -e BACKEND=myapp:8080 ghcr.io/coreruleset/coraza-crs:caddy-alpine
```

Test that the WAF is working:

```bash
# Normal request — should return 200
curl http://localhost/

# SQL injection — should return 403
curl "http://localhost/?id=1%20AND%201=1"
```

## Env Variables

### Coraza Specific

| Variable | Default | Description |
| - | - | - |
| CORAZA_RULE_ENGINE | `On` | Enable Coraza. Accepted: `On`, `Off`, `DetectionOnly` |
| CORAZA_REQ_BODY_ACCESS | `"On"` | Allow Coraza to access request bodies |
| CORAZA_REQ_BODY_LIMIT | `13107200` | Maximum request body size for buffering |
| CORAZA_REQ_BODY_NOFILES_LIMIT | `524288` | Maximum request body size excluding files |
| CORAZA_REQ_BODY_LIMIT_ACTION | `"Reject"` | Action on body limit: `Reject`, `ProcessPartial` |
| CORAZA_REQ_BODY_JSON_DEPTH_LIMIT | `1024` | Maximum JSON depth |
| CORAZA_ARGUMENTS_LIMIT | `1000` | Maximum number of arguments |
| CORAZA_RESP_BODY_ACCESS | `"On"` | Allow Coraza to access response bodies |
| CORAZA_RESP_BODY_LIMIT | `1048576` | Maximum response body size for buffering |
| CORAZA_RESP_BODY_LIMIT_ACTION | `"ProcessPartial"` | Action on response body limit |
| CORAZA_RESP_BODY_MIMETYPE | `"text/plain text/html text/xml"` | MIME types to inspect |
| CORAZA_AUDIT_ENGINE | `"RelevantOnly"` | Audit engine mode |
| CORAZA_AUDIT_LOG | `/dev/stdout` | Audit log destination |
| CORAZA_AUDIT_LOG_FORMAT | `JSON` | Audit log format: `JSON`, `Native` |
| CORAZA_AUDIT_LOG_PARTS | `'ABIJDEFHZ'` | Which transaction parts to log |
| CORAZA_AUDIT_LOG_RELEVANT_STATUS | `"^(?:5\|4[0-9][0-35-9])"` | HTTP status codes relevant for logging |
| CORAZA_AUDIT_LOG_TYPE | `Serial` | Audit log type |
| CORAZA_AUDIT_STORAGE_DIR | `/var/log/coraza/audit/` | Audit log storage directory |
| CORAZA_DATA_DIR | `/tmp/coraza/data` | Persistent data directory |
| CORAZA_TMP_DIR | `/tmp/coraza` | Temporary files directory |
| CORAZA_DEBUG_LOG | `/dev/null` | Debug log file |
| CORAZA_DEBUG_LOGLEVEL | `1` | Debug log level (1-9) |

### CRS Specific

| Variable | Default | Description |
| - | - | - |
| PARANOIA | `1` | CRS Paranoia Level for logging |
| ANOMALY_INBOUND | `5` | Inbound anomaly score threshold |
| ANOMALY_OUTBOUND | `4` | Outbound anomaly score threshold |
| BLOCKING_PARANOIA | `1` | CRS Paranoia Level for blocking |

### Web Server Specific

#### Caddy

| Variable | Default | Description |
| - | - | - |
| BACKEND | `localhost:80` | Backend `host:port` to proxy to |
| PORT | `8080` | Listen port |
| ACCESSLOG | `/var/log/caddy/access.log` | Access log path |
| CORAZA_TAG | `coraza` | Default tag for CRS rules |

#### nginx

| Variable | Default | Description |
| - | - | - |
| BACKEND | `localhost:80` | Backend `host:port` to proxy to |
| PORT | `80` | Listen port |
| NGINX_LOGLEVEL | `warn` | nginx error log level |

#### Apache

| Variable | Default | Description |
| - | - | - |
| BACKEND | `localhost:80` | Backend `host:port` to proxy to |
| PORT | `80` | Listen port |

## Important Notes

- **Caddy** runs as a non-root user by default. The `cap_net_bind_service` capability is added to allow binding on ports < 1024. Default port is 8080.
- **nginx and Apache** use Ubuntu 24.04 with packages from [PPA](https://launchpad.net/~pierrepomes). Platforms: `linux/amd64` and `linux/arm64`.
- The audit log defaults to `/dev/stdout` (visible via `docker logs`).

## Configuration Files/Directories

The following configuration paths are shared across all variants:

| Path | Description |
| ---- | ----------- |
| `/opt/coraza/config/coraza.conf` | Main Coraza WAF configuration |
| `/opt/coraza/config/coraza-rules.conf` | Rule include chain (nginx/Apache) |
| `/opt/coraza/config/crs-setup.conf` | OWASP CRS configuration |
| `/opt/coraza/config.d/*.conf` | User configuration files |
| `/opt/coraza/owasp-crs/rules/*.conf` | OWASP CRS rule files |
| `/opt/coraza/owasp-crs/plugins/*.conf` | CRS plugins |
| `/opt/coraza/plugins/*.conf` | User plugins |
| `/opt/coraza/rules/*.conf` | Additional built-in rules |
| `/opt/coraza/rules.d/*.conf` | User defined rule sets |
| `/opt/coraza/overrides/*.conf` | Rule/configuration overrides |

## Build Arguments

| Variable | Default | Description |
| -------- | ------- | ----------- |
| `CRS_VERSION` | `4.24.1` | OWASP CRS release version |
| `CADDY_VERSION` | `2.8.4` | Caddy Docker tag (caddy variant) |
| `UBUNTU_VERSION` | `24.04` | Ubuntu base image (nginx/apache variants) |

## Building

We require `buildx` >= v0.9.1. See [official documentation](https://docs.docker.com/build/architecture/#install-buildx).

```bash
# See all build targets
docker buildx bake -f ./docker-bake.hcl --print

# Build all targets
docker buildx create --use --platform linux/amd64,linux/arm64
docker buildx bake -f docker-bake.hcl

# Build a single target
docker buildx bake -f docker-bake.hcl --set "*.platform=linux/amd64" nginx-ubuntu
```

## Advanced Configuration

### Supplemental Configuration

Add Coraza configuration without overwriting defaults by mounting `*.conf` files into:

- `/opt/coraza/config.d` — additional configuration
- `/opt/coraza/rules.d` — additional rule sets

### CRS Plugins

Download and mount plugins to `/opt/coraza/plugins`:

```bash
curl -sSL https://github.com/coreruleset/wordpress-rule-exclusions-plugin/archive/refs/tags/v1.0.0.tar.gz -o wordpress.tar.gz
tar xvf wordpress.tar.gz --strip-components 1 'wordpress-rule-exclusions-plugin*/plugins'
docker run -v $(pwd)/plugins:/opt/coraza/plugins ghcr.io/coreruleset/coraza-crs:nginx-ubuntu
```

### Replacement Configuration

To use your own web server configuration, mount it at:

- **Caddy**: `/config/caddy/Caddyfile`
- **nginx**: `/config/nginx/nginx.conf`
- **Apache**: `/config/apache/vhost.conf`

To replace the Coraza configuration entirely, mount at `/config/coraza/coraza.conf`.

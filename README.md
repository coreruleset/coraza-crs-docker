# Coraza CRS Docker

Docker containers running [OWASP Coraza WAF](https://coraza.io/) with the [OWASP Core Rule Set (CRS)](https://github.com/coreruleset/coreruleset).

Three web server variants are available:

| Variant | Base | Image Tag |
| ------- | ---- | --------- |
| [Caddy](https://caddyserver.com/) | Alpine 3.20 | `caddy-alpine` |
| [nginx](https://nginx.org/) | Debian (nginx-unprivileged) | `nginx` |
| [Apache](https://httpd.apache.org/) | Debian (httpd) | `apache` |

The containers act as a reverse proxy, inspecting traffic with Coraza WAF and CRS before forwarding to a backend service.

## Supported Tags

### Stable Tags

Stable tags include the CRS version and a timestamp: `<CRS version>-<variant>-<date>`.

Examples:
   * `4-caddy-alpine-202509051009`
   * `4.25-nginx-202509051009`
   * `4.25.0-apache-202509051009`

### Rolling Tags

Rolling tags are updated on every release and always point to the latest build. They should not be used in production.

Examples:
   * `caddy-alpine`
   * `nginx`
   * `apache`

### LTS Tags

LTS (Long-Term Support) tags point to a designated LTS release and are updated less frequently than stable tags.

The LTS tag format is `<CRS version>-<variant>-lts`.

Examples:
   * `4.25-caddy-alpine-lts`
   * `4.25.0-nginx-lts`
   * `4.25-apache-lts`

- [Coraza CRS Docker](#coraza-crs-docker)
  - [Supported Tags](#supported-tags)
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
# Caddy (port 8080)
docker compose --profile caddy up

# nginx (port 8081)
docker compose --profile nginx up

# Apache (port 8082)
docker compose --profile apache up

# All three
docker compose --profile all up
```

Or run directly:

```bash
# nginx (non-root, listens on 8080)
docker run -d -p 8080:8080 -e BACKEND=myapp:8080 ghcr.io/coreruleset/coraza-crs:nginx

# Apache
docker run -d -p 80:80 -e BACKEND=myapp:8080 ghcr.io/coreruleset/coraza-crs:apache

# Caddy
docker run -d -p 8080:8080 -e BACKEND=myapp:8080 ghcr.io/coreruleset/coraza-crs:caddy-alpine
```

Test that the WAF is working (adjust port to match the variant: 8080 for Caddy, 8081 for nginx, 8082 for Apache):

```bash
# Normal request — should return 200
curl http://localhost:8081/

# SQL injection — should return 403
curl "http://localhost:8081/?id=1%20AND%201=1"
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

These variables apply to all variants (nginx, Apache, Caddy). Not every setting translates perfectly across servers — when a variable doesn't map to something meaningful, it's ignored on that variant.

| Variable | Default | Description | nginx | Apache | Caddy |
| - | - | - | :-: | :-: | :-: |
| `BACKEND` | `localhost:80` | Backend `host:port` to proxy to | ✅ | ✅ | ✅ |
| `PORT` | `8080` | Listen port | ✅ | ✅ | ✅ |
| `SERVER_NAME` | `localhost` | Server name | ✅ | ✅ | — |
| `SERVER_TOKENS` | `off` (nginx/caddy), `Prod` (apache) | Hide server version info | ✅ | ✅ | — |
| `WORKER_CONNECTIONS` | `1024` | Max concurrent connections per worker | ✅ | ✅ | — |
| `KEEPALIVE_TIMEOUT` | `60s` | Client keepalive timeout | ✅ | ✅ | ✅ |
| `PROXY_TIMEOUT` | `60s` | Backend proxy timeout | ✅ | ✅ | ✅ |
| `LOGLEVEL` | `warn` | Server error log level | ✅ | ✅ | ✅ |
| `ACCESSLOG` | `/dev/stdout` | Access log destination | ✅ | ✅ | ✅ |
| `ERRORLOG` | `/dev/stderr` | Error log destination | ✅ | ✅ | — |
| `SSL_PORT` | `8443` | HTTPS listen port | ✅ | ✅ | — |
| `SSL_CERT_FILE` | (auto-generated) | TLS certificate path | ✅ | ✅ | — |
| `SSL_CERT_KEY_FILE` | (auto-generated) | TLS private key path | ✅ | ✅ | — |
| `SSL_PROTOCOLS` | nginx: `TLSv1.2 TLSv1.3`, apache: `all -SSLv3 -TLSv1 -TLSv1.1` | Allowed TLS protocols (syntax differs per server) | ✅ | ✅ | — |
| `SSL_CIPHERS` | [Mozilla intermediate](https://ssl-config.mozilla.org/) | TLS cipher suites | ✅ | ✅ | — |
| `SSL_PREFER_CIPHERS` | `off` | Prefer server ciphers | ✅ | — | — |
| `SSL_DH_BITS` | `2048` | DH parameter size (2048/4096) | ✅ | — | — |
| `SSL_OCSP_STAPLING` | `off` | OCSP stapling | ✅ | — | — |
| `SSL_VERIFY` | `off` | Client certificate verification | ✅ | — | — |
| `SSL_VERIFY_DEPTH` | `1` | Client cert chain depth | ✅ | — | — |

A self-signed certificate is generated automatically at startup if no certificate is mounted. To use your own certificate, mount it at the `SSL_CERT_FILE` and `SSL_CERT_KEY_FILE` paths. Caddy handles TLS automatically via its built-in ACME support.

#### Caddy-only

| Variable | Default | Description |
| - | - | - |
| `CORAZA_TAG` | `coraza` | Default tag for CRS rules |

## Important Notes

- **Caddy** runs as a non-root user by default. The `cap_net_bind_service` capability is added to allow binding on ports < 1024. Default port is 8080.
- **nginx** uses `nginxinc/nginx-unprivileged` (Debian-based, non-root). **Apache** uses `httpd` (Debian-based). Both build libcoraza and connector modules from source. Platforms: `linux/amd64` and `linux/arm64`.
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
| `CRS_VERSION` | `4.25.0` | OWASP CRS release version (LTS) |
| `CADDY_VERSION` | `2.11.2` | Caddy Docker tag (caddy variant) |
| `NGINX_VERSION` | `1.28.2` | nginx image version (nginx variant) |
| `HTTPD_VERSION` | `2.4` | httpd image version (apache variant) |
| `LIBCORAZA_VERSION` | `v1.2.0` | libcoraza release (nginx/apache variants) |
| `CORAZA_NGINX_VERSION` | `0.10.1` | coraza-nginx release (nginx variant) |
| `CORAZA_APACHE_VERSION` | `0.0.1` | coraza-apache release (apache variant) |

## Building

We require `buildx` >= v0.9.1. See [official documentation](https://docs.docker.com/build/architecture/#install-buildx).

```bash
# See all build targets
docker buildx bake -f ./docker-bake.hcl --print

# Build all targets
docker buildx create --use --platform linux/amd64,linux/arm64
docker buildx bake -f docker-bake.hcl

# Build a single target
docker buildx bake -f docker-bake.hcl --set "*.platform=linux/amd64" nginx
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
docker run -v $(pwd)/plugins:/opt/coraza/plugins ghcr.io/coreruleset/coraza-crs:nginx
```

### Replacement Configuration

To use your own web server configuration, mount it at:

- **Caddy**: `/config/caddy/Caddyfile`
- **nginx**: `/config/nginx/nginx.conf`
- **Apache**: `/config/apache/coraza.conf`

To replace the Coraza configuration entirely, mount at `/config/coraza/coraza.conf`.

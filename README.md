# Coraza WAF with Caddy

This is based on the work made by https://github.com/docker-servers/coraza-caddy

This repository contains a Docker container running [Caddy](https://caddyserver.com/) with the [OWASP Coraza WAF](https://coraza.io/). The container is designed to be used as a WAF for a Docker service. The [OWASP CRS](https://github.com/coreruleset/coreruleset) will be used by default.

Currently, the assumption is made that this acts as an intermediate proxy between the ingress and the service to protect. There is no SSL configuration, rather than should be handled at the ingress.

- [Coraza WAF with Caddy](#coraza-waf-with-caddy)
  - [Examples](#examples)
  - [Env Variables](#env-variables)
    - [Coraza Specific](#coraza-specific)
    - [Caddy Specific](#caddy-specific)
  - [Important Notes](#important-notes)
  - [Configuration Files/Directories](#configuration-filesdirectories)
  - [Build Arguments](#build-arguments)
  - [Advanced Configuration](#advanced-configuration)
    - [Supplemental Configuration](#supplemental-configuration)
    - [Replacement Configuration - Caddy](#replacement-configuration---caddy)
    - [Replacement Configuration - Coraza](#replacement-configuration---coraza)

## Env Variables

The following env variables may be set to control Caddy and Coraza.

### Coraza Specific

These values control Coraza.

| Variable | Default | Documentation |
| - | - | - |
| CORAZA_ARGUMENTS_LIMIT | Default: `1000` | An integer indicating the maximum number of arguments that can be processed before setting the `REQBODY_ERROR` variable |
| CORAZA_AUDIT_ENGINE | Default: `"RelevantOnly"` | |
| CORAZA_AUDIT_LOG | Default: `/dev/stdout` | A string indicating the path to the main audit log file or the concurrent logging index file |
| CORAZA_AUDIT_LOG_FORMAT | Default: `JSON` | A string indicating the output format of the AuditLogs (Default: `JSON`). Accepted values: `JSON`, `Native`. See [SecAuditLogFormat]() |
| CORAZA_AUDIT_LOG_PARTS | Default: `'ABIJDEFHZ'` | A string that defines which parts of each transaction are going to be recorded in the audit log (Default: `'ABIJDEFHZ'`). See [SecAuditLogParts]() for the accepted values. |
| CORAZA_AUDIT_LOG_RELEVANT_STATUS | Default: `"^(?:5\|4[0-9][0-35-9])"` | A regular expression string that defines the http error codes that are relevant for audit logging (Default: `"^(?:5|4(?!04))"`). See [SecAuditLogRelevantStatus]() |
| CORAZA_AUDIT_LOG_TYPE | Default: `Serial` | |
| CORAZA_AUDIT_STORAGE_DIR | Default: `/var/log/coraza/audit/` | |
| CORAZA_DATA_DIR | Default: `/tmp/coraza/data` | |
| CORAZA_DEBUG_LOG | Default: `/dev/null` | |
| CORAZA_DEFAULT_PHASE1_ACTION | Default: `"phase:1,pass,log,tag:'\${CORAZA_TAG}'"` | String with the contents for the default action in phase 1 |
| CORAZA_DEFAULT_PHASE2_ACTION | Default: `"phase:2,pass,log,tag:'\${CORAZA_TAG}'"` | String with the contents for the default action in phase 2 |
| CORAZA_REQ_BODY_ACCESS | Default: `"On"` | A string value allowing ModSecurity to access request bodies. Allowed values: `On`, `Off`. See [SecRequestBodyAccess]() |
| CORAZA_REQ_BODY_JSON_DEPTH_LIMIT | Default: `1024` | |
| CORAZA_REQ_BODY_LIMIT | Default: `13107200` | An integer value indicating the maximum request body size accepted for buffering. See [SecRequestBodyLimit]() |
| CORAZA_REQ_BODY_LIMIT_ACTION | Default: `"Reject"` | A string value for the action when `SecRequestBodyLimit` is reached. Accepted values: `Reject`, `ProcessPartial`. See [SecRequestBodyLimitAction]() |
| CORAZA_REQ_BODY_NOFILES_LIMIT | Default: `524288` | |
| CORAZA_RESP_BODY_ACCESS | Default: `"On"` | A string value allowing ModSecurity to access response bodies. Allowed values: `On`, `Off`. See [SecResponseBodyAccess]() |
| CORAZA_RESP_BODY_LIMIT | Default: `1048576` | An integer value indicating the maximum response body size accepted for buffering. |
| CORAZA_RESP_BODY_LIMIT_ACTION | Default: `"ProcessPartial"` | A string value for the action when `SecResponseBodyLimit` is reached. Accepted values: `Reject`, `ProcessPartial`. See [SecResponseBodyLimitAction]() |
| CORAZA_RESP_BODY_MIMETYPE | Default: `"text/plain text/html text/xml"` | |
| CORAZA_RULE_ENGINE | Default: `On` | A string value enabling Coraza itself. Accepted values: `On`, `Off`, `DetectionOnly`. See [SecRuleEngine]() |
| CORAZA_TAG | Default: `coraza` | A string indicating the default tag action, which will be inherited by the rules in the same configuration context. |
| CORAZA_TMP_DIR | Default: `/tmp/coraza` | A string indicating the path where temporary files will be created |

### CRS Specific

| Variable | Default | Documentation |
| - | - | - |
| PARANOIA | Default: `1` | CRS Paranoia Level setting for logging. It could be different from the BLOCKING level, allowing you to log additional information. |
| ANOMALY_INBOUND | Default: `5` | The score used by CRS to block incoming requests. |
| ANOMALY_OUTBOUND | Default: `4` | The score used by CRS to block outgoing requests. |
| BLOCKING_PARANOIA | Default: `1` | CRS Paranoia Level setting used for blocking |

### Caddy Specific

These values control Caddy.

| Variable | Default | Documentation |
| - | - | - |
| ACCESSLOG | Default: `stderr` | Log to this file access logs. Use `/var/log/caddy/access.log` or similar if you want to store it in the filesystem |
| BACKEND | Default: `localhost:80` | Proxy traffic to this `host:port` |
| PORT | Default: `8080` | Port where the server listens. |

## Important Notes

- The container is configured by default to run as a non-root user. The upstream Caddy containers run using root by default. To allow binding on ports <1024 `cap_net_bind_service` is added on the Caddy binary. The default port still is 8080.

## Configuration Files/Directories

The following configuration files/directories exist within the container:

- `/opt/coraza/config/coraza.conf`: The main Coraza configuration file.
- `/opt/coraza/config.d/*.conf`: User defined configuration files. See the [Supplemental Configuration](#supplemental-configuration) section for more information.
- `/opt/coraza/config/crs-setup.conf`: The OWASP Core Rule Set configuration file.
- `/opt/coraza/owasp-crs/*.conf`: The OWASP Core Rule Set rule files.
- `/opt/coraza/rules/*.conf`: Other default rules added by this image. Currently this is not used.
- `/opt/coraza/rules.d/*.conf`: Any user defined rule sets.
- `/config/caddy`: Caddy configuration directory. The Caddyfile generated from template is located here.
- `/data/caddy`: Caddy data directory. Things like SSL certificates are located here.

## Build Arguments

Various arguments can be provided if building the container yourself. The available arguments are:

| Variable           | Default      | Description                                                                                                                                                  |
| ------------------ | ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `CADDY_VERSION`    | `2.8.1`      | The Caddy Docker container tag to use as a base.                                                                                                             |
| `CRS_VERSION`      | `v4.5.0`     | The OWASP CRS release.                                                                                                                                       |
| `LIBCAP`           | `true`       | Install libcap and add the `cap_net_bind_service` capability to the Caddy binary. Required for the container to bind to low ports when not running as root.  |
| `CADDY_USER`       | `caddy`      | The user name that will run Caddy. Can be set to `root` to run Caddy as root rather than a low privleged user.                                               |
| `CADDY_GROUP`      | `caddy`      | The group name for the Caddy user. Can be set to `root` to run Caddy as root rather than a low privleged user.                                               |
| `CADDY_UID`        | `1000`       | The UID of the user that will run Caddy. Ignored if the `CADDY_USER` argument is `root`.                                                                     |
| `CADDY_GID`        | `1000`       | The GID of the user that will run Caddy. Ignored if the `CADDY_USER` argument is `root`.                                                                     |
| `CADDY_CONFIG_DIR` | `/config`    | The Caddy configuration directory.                                                                                                                           |
| `CADDY_DATA_DIR`   | `/data`      | The Caddy data directory. SSL certificates will be stored here if Caddy will be generating them for you. It is recommended that this be mounted as a volume. |

### Building

We require a version of `buildx` >= v0.9.1. [Visit the official documentation](https://docs.docker.com/build/architecture/#install-buildx) for instructions on installing and upgrading `buildx`. You can check which version you have using:

```bash
docker buildx version
github.com/docker/buildx v0.9.1 ed00243a0ce2a0aee75311b06e32d33b44729689
```

If you want to see the targets of the build, use:

```bash
docker buildx bake -f ./docker-bake.hcl --print
```

To build for any platforms of your choosing, just use this example:

```bash
docker buildx create --use --platform linux/amd64,linux/i386,linux/arm64,linux/arm/v7
docker buildx bake -f docker-bake.hcl
```

To build a specific target for a single platform only (replace target and platform strings in the example with the your choices):

```bash
docker buildx bake -f docker-bake.hcl --set "*.platform=linux/amd64" caddy-alpine

## Advanced Configuration

If you prefer to configure Caddy and/or Coraza yourself there are multiple options.

### Supplemental Configuration

To add Coraza configuration without overwriting any of the container default configurations, `*.conf` files are loaded from these directories:

- `/opt/coraza/config.d`
- `/opt/coraza/rules.d`

As an example, you may want to create your own rules for Coraza. You would create a volume and mount it in the container at `/opt/coraza/rules.d`; the rules will then be loaded on server start automatically.

## Adding CRS Plugins

To add CRS Plugins, download and decompress the plugin to a directory of your choice. The official plugin list is at https://github.com/coreruleset/plugin-registry.

Create a volume or bind mount a directory of your choice to `/opt/coraza/plugins`; the rules will then be loaded on server start automatically.

Example:
```
curl -sSL https://github.com/coreruleset/wordpress-rule-exclusions-plugin/archive/refs/tags/v1.0.0.tar.gz -o wordpress.tar.gz
tar xvf wordpress.tar.gz --strip-components 1 'wordpress-rule-exclusions-plugin*/plugins'
❯ docker compose run -v $(pwd)/plugins:/opt/coraza/plugins coraza-crs
[+] Creating 1/0
 ✔ Container coraza-crs-docker-whoami-1  Running                                                                                        0.0s
Generating configuration files...
  - Caddyfile
    - Generating Caddyfile from template /templates/Caddyfile
    - Done
  - Coraza configuration file
    - Generating Caddyfile from template /templates/coraza.conf
    - Done
  - User configuration files loaded from /opt/coraza/config.d
    - Done
  - Loading user plugins from /opt/coraza/plugins
    -> wordpress-rule-exclusions-before.conf
    -> wordpress-rule-exclusions-config.conf
    - Done
  - Loading user defined rule sets from /opt/coraza/rules.d
    - Done
```

### Replacement Configuration - Caddy

If you prefer to use your own configuration file for Caddy, simply mount the configuration file as `/config/caddy/Caddyfile` or mount a volume at `/config/Caddy` with a `Caddyfile` inside. You will need to add the relevant Coraza configuration to Caddy yourself if you choose this option. The bare minimum recommended configuration is:

```bash
# Ensure Coraza WAF runs first - this must be included for Coraza to be working
{
  order coraza_waf first
}

# Create the HTTP listener
:80 {

  # Load Coraza configuration
  coraza_waf {
    # Main configuration file
    include /opt/coraza/config/coraza.conf
    # User defined configuration files
    include /opt/coraza/config.d/*.conf
    # OWASP CRS Setup
    include /opt/coraza/config/crs-setup.conf
    # OWASP CRS Plugins Setup
    include /opt/coraza/owasp-crs/plugins/*-config.conf
    include /opt/coraza/owasp-crs/plugins/*-before.conf
    # OWASP CRS
    include /opt/coraza/owasp-crs/*.conf
    # OWASP CRS Plugins After
    include /opt/coraza/owasp-crs/plugins/*-after.conf
    # Other baked in rule sets
    include /opt/coraza/rules/*.conf
    # User defined rule sets
    include /opt/coraza/rules.d/*.conf
  }

  ...
```

### Replacement Configuration - Coraza

To completely replace the Coraza configuration, create a volume and mount it in the container at `/opt/coraza`. Check the [Configuration Files/Directories](#configuration-filesdirectories) section for the expected configuration files.

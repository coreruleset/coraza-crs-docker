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

| Variable                      | Default         | Documentation                                                                                                       |
| ----------------------------- | --------------- | ------------------------------------------------------------------------------------------------------------------- |
| `CORAZA_SECRULEENGINE`        | `DetectionOnly` | [SecRuleEngine](https://github.com/SpiderLabs/ModSecurity/wiki/Reference-Manual-(v2.x)#SecRuleEngine)               |
| `CORAZA_SECREQUESTBODYACCESS` | `On`            | [SecRequestBodyAccess](https://github.com/SpiderLabs/ModSecurity/wiki/Reference-Manual-(v2.x)#SecRequestBodyAccess) |
| `CORAZA_REMOVERULEIDS`        | ``              | [SecRuleRemoveById](https://github.com/SpiderLabs/ModSecurity/wiki/Reference-Manual-(v2.x)#secruleremovebyid)       |

### Caddy Specific

These values control Caddy.

## Important Notes

- The container is configured by default to run as a non-root user. The upstream Caddy containers run using root by default. To allow binding on ports <1024 `cap_net_bind_service` is added on the Caddy binary.

- Buildkit must be used to build the Docker image:

```bash
docker build -t caddy-coraza-waf ./alpine
```

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
| `CADDY_TAG`        | `2.6.2`      | The Caddy Docker container tag to use as a base.                                                                                                             |
| `CRS_TAG`          | `v4.3.0` | The OWASP Core Rule Set release tag.                                                                                                                         |
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
    # OWASP Core Rule Set (CRS) Setup
    include /opt/coraza/config/crs-setup.conf
    # OWASP Core Rule Set (CRS)
    include /opt/coraza/owasp-crs/*.conf
    # Other baked in rule sets
    include /opt/coraza/rules/*.conf
    # User defined rule sets
    include /opt/coraza/rules.d/*.conf
  }

  ...
```

### Replacement Configuration - Coraza

To completely replace the Coraza configuration, create a volume and mount it in the container at `/opt/coraza`. Check the [Configuration Files/Directories](#configuration-filesdirectories) section for the expected configuration files.

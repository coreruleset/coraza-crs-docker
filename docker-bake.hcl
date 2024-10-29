# docker-bake.hcl
variable "crs-version" {
    # renovate: depName=coreruleset/coreruleset datasource=github-releases
    default = "4.8.0"
}

variable "caddy-version" {
    # renovate: depName=caddy datasource=docker
    default = "2.8.4"
}

variable "coraza-version" {
    # renovate: depName=corazawaf/coraza-caddy datasource=github-releases
    default = "v2.0.0-rc.3"
}


variable "REPOS" {
    # List of repositories to tag
    default = [
      #"owasp/coraza-crs",
        "ghcr.io/coreruleset/coraza-crs",
    ]
}

function "major" {
    params = [version]
    result = split(".", version)[0]
}

function "minor" {
    params = [version]
    result = join(".", slice(split(".", version),0,2))
}

function "patch" {
    params = [version]
    result = join(".", slice(split(".", version),0,3))
}

function "tag" {
    params = [tag]
    result = [for repo in REPOS : "${repo}:${tag}"]
}

function "vtag" {
    params = [semver, variant]
    result = concat(
        tag("${major(semver)}-${variant}-${formatdate("YYYYMMDDHHMM", timestamp())}"),
        tag("${minor(semver)}-${variant}-${formatdate("YYYYMMDDHHMM", timestamp())}"),
        tag("${patch(semver)}-${variant}-${formatdate("YYYYMMDDHHMM", timestamp())}")
    )
}

group "default" {
    targets = [
        "caddy-alpine",
    ]
}

target "docker-metadata-action" {}

target "platforms-base" {
    inherits = ["docker-metadata-action"]
    context="."    
    platforms = ["linux/amd64", "linux/arm/v6", "linux/arm/v7", "linux/arm64"]
    labels = {
        "org.opencontainers.image.source" = "https://github.com/coreruleset/coraza-crs-docker"
    }
    args = {
        CRS_VERSION = "${crs-version}"
        CADDY_VERSION = "${caddy-version}"
        CORAZA_VERSION = "${coraza-version}"
    }
}

target "caddy-alpine" {
    inherits = ["platforms-base"]
    context="."
    dockerfile="caddy/Dockerfile"
    tags = concat(tag("caddy-alpine"),
        vtag("${crs-version}", "caddy-alpine")
    )
}

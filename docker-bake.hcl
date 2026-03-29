# docker-bake.hcl
variable "crs-version" {
    # renovate: depName=coreruleset/coreruleset datasource=github-releases
    default = "4.25.0"
}

variable "v4-lts-crs-version" {
    default = "4.25.0"
}

variable "crs-versions" {
    default = {
        "lts"    = v4-lts-crs-version,
        "latest" = crs-version
    }
}

variable "caddy-version" {
    # renovate: depName=caddy datasource=docker
    default = "2.11.2"
}

variable "coraza-version" {
    # renovate: depName=corazawaf/coraza-caddy datasource=github-releases
    default = "v2.3.0"
}

variable "golang-version" {
    # renovate: depName=golang datasource=docker
    default = "1.25"
}

variable "libcoraza-version" {
    # renovate: depName=corazawaf/libcoraza datasource=github-releases
    default = "v1.2.1"
}

variable "coraza-nginx-version" {
    # renovate: depName=corazawaf/coraza-nginx datasource=github-releases
    default = "0.10.1"
}

variable "coraza-apache-version" {
    # renovate: depName=corazawaf/coraza-apache datasource=github-releases
    default = "0.0.1"
}

variable "nginx-version" {
    # renovate: depName=nginxinc/nginx-unprivileged datasource=docker
    default = "1.29.5"
}

variable "httpd-version" {
    # renovate: depName=httpd datasource=docker
    default = "2.4"
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

function "lts-tag" {
    params = [semver, variant]
    result = concat(
        tag("${minor(semver)}-${variant}-lts"),
        tag("${patch(semver)}-${variant}-lts")
    )
}

group "default" {
    targets = [
        "caddy-alpine",
        "nginx",
        "apache",
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
        CADDY_VERSION = "${caddy-version}"
        CORAZA_VERSION = "${coraza-version}"
    }
}

target "caddy-alpine" {
    matrix = {
        crs_release = crs-versions
    }
    inherits = ["platforms-base"]
    name = "caddy-alpine-${replace(crs_release, ".", "-")}"
    context="."
    dockerfile="caddy/Dockerfile"
    args = {
        CRS_VERSION = crs_release
    }
    tags = concat(
        tag("caddy-alpine"),
        vtag("${crs_release}", "caddy-alpine"),
        equal(crs_release, v4-lts-crs-version) ? lts-tag("${crs_release}", "caddy-alpine") : []
    )
}

target "nginx" {
    matrix = {
        crs_release = crs-versions
    }
    inherits = ["platforms-base"]
    name = "nginx-${replace(crs_release, ".", "-")}"
    context="."
    dockerfile="nginx/Dockerfile"
    platforms = ["linux/amd64", "linux/arm64"]
    args = {
        CRS_VERSION = crs_release
        GOLANG_VERSION = "${golang-version}"
        LIBCORAZA_VERSION = "${libcoraza-version}"
        CORAZA_NGINX_VERSION = "${coraza-nginx-version}"
        NGINX_VERSION = "${nginx-version}"
    }
    tags = concat(
        tag("nginx"),
        vtag("${crs_release}", "nginx"),
        equal(crs_release, v4-lts-crs-version) ? lts-tag("${crs_release}", "nginx") : []
    )
}

target "apache" {
    matrix = {
        crs_release = crs-versions
    }
    inherits = ["platforms-base"]
    name = "apache-${replace(crs_release, ".", "-")}"
    context="."
    dockerfile="apache/Dockerfile"
    platforms = ["linux/amd64", "linux/arm64"]
    args = {
        CRS_VERSION = crs_release
        GOLANG_VERSION = "${golang-version}"
        LIBCORAZA_VERSION = "${libcoraza-version}"
        CORAZA_APACHE_VERSION = "${coraza-apache-version}"
        HTTPD_VERSION = "${httpd-version}"
    }
    tags = concat(
        tag("apache"),
        vtag("${crs_release}", "apache"),
        equal(crs_release, v4-lts-crs-version) ? lts-tag("${crs_release}", "apache") : []
    )
}

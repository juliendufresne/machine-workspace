# Dev toolbox image: a pinned shellcheck + shellspec so local runs and CI use
# byte-identical tooling. Built by `make tools-build`; versions come from the
# Makefile build-args (override through .env / .env.local).
ARG UBUNTU_VERSION=26.04
FROM ubuntu:${UBUNTU_VERSION}

ARG SHELLCHECK_VERSION=0.11.0
ARG SHELLSPEC_VERSION=0.28.1

# kcov powers `shellspec --kcov`; its version is pinned by UBUNTU_VERSION.
# python3 + python3-yaml back dev/bin/github_workflow_scan.py; git (already
# needed for shellspec below) lets it resolve action tags to SHAs for
# `make github-actions-outdated` / `-update`.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash ca-certificates curl git xz-utils kcov python3 python3-yaml \
    && rm -rf /var/lib/apt/lists/*

# shellcheck: pinned static release binary.
RUN curl -fsSL \
        "https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/shellcheck-v${SHELLCHECK_VERSION}.linux.x86_64.tar.xz" \
    | tar -xJ -C /tmp \
    && install -m 0755 "/tmp/shellcheck-v${SHELLCHECK_VERSION}/shellcheck" /usr/local/bin/shellcheck \
    && rm -rf "/tmp/shellcheck-v${SHELLCHECK_VERSION}"

# shellspec: pinned tag, linked onto PATH.
RUN git clone --depth 1 --branch "${SHELLSPEC_VERSION}" \
        https://github.com/shellspec/shellspec.git /opt/shellspec \
    && ln -s /opt/shellspec/shellspec /usr/local/bin/shellspec

WORKDIR /work

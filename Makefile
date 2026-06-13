# Optional, untracked overrides take precedence over the tracked defaults.
-include .env
-include .env.local

.DEFAULT_GOAL := help

# Name (tag) of the locally built dev toolbox image and the versions baked into
# it. Override any of these through .env / .env.local.
DEV_TOOL_IMAGE ?= workspace-dev-tools
UBUNTU_VERSION ?= 26.04
SHELLCHECK_VERSION ?= 0.11.0
SHELLSPEC_VERSION ?= 0.28.1

DEV_TOOL_CONTEXT := dev/docker/dev-tools
DEV_TOOL_DOCKERFILE := $(DEV_TOOL_CONTEXT)/Dockerfile

# Pretty progress line.
log = printf '\033[1;34m▶ %s\033[0m\n' "$(1)"

# Every shell script under bin/, lib/ and libexec/, plus the POSIX bootstrap,
# detected by its shebang so newly added scripts (including the extensionless
# libexec actions and the identity toolkit) are linted automatically without
# editing this list.
SHELL_SCRIPTS := $(shell \
	find bin lib libexec install.sh -type f \
		-exec sh -c 'head -n1 "$$1" | grep -Eq "^#!.*\b(ba)?sh\b"' _ {} \; \
		-print 2>/dev/null)

# Base invocation of the dev toolbox: the container runs as the host user so
# nothing it writes is root-owned, and the working directory is the bind-mounted
# repository. The mount mode is supplied per target.
_DOCKER_BASE := docker run --rm \
	--workdir /work \
	--user "$(shell id -u):$(shell id -g)"

# Read-only mount: lint and test write only under the container's temp dir, so
# :ro is safe and keeps the host tree untouched.
_DOCKER_RUN := $(_DOCKER_BASE) --volume "$(CURDIR):/work:ro" $(DEV_TOOL_IMAGE)

# Read-write mount: coverage writes its report to var/coverage/ in the host tree.
_DOCKER_RUN_RW := $(_DOCKER_BASE) --volume "$(CURDIR):/work" $(DEV_TOOL_IMAGE)

# kcov options: shellspec's defaults (passing --kcov-options replaces them, so
# they are restated here) plus /dev/test/ so the spec files themselves are kept
# out of the coverage figures. /libexec/ joins the include pattern so the
# extensionless action scripts (which carry the moved create/remove/show logic) are
# instrumented alongside the .sh libraries.
KCOV_OPTIONS := --include-path=. --include-pattern=.sh,/libexec/ \
	--exclude-pattern=/.shellspec,/spec/,/coverage/,/report/,/dev/test/ \
	--path-strip-level=1

.PHONY: tools-build
tools-build: ## Build the dev toolbox image
	@$(call log,building $(DEV_TOOL_IMAGE))
	docker build \
		--tag $(DEV_TOOL_IMAGE) \
		--build-arg UBUNTU_VERSION=$(UBUNTU_VERSION) \
		--build-arg SHELLCHECK_VERSION=$(SHELLCHECK_VERSION) \
		--build-arg SHELLSPEC_VERSION=$(SHELLSPEC_VERSION) \
		$(DEV_TOOL_CONTEXT)

.PHONY: tools-ensure
tools-ensure: ## Build the dev toolbox image when it is missing
	@docker image inspect $(DEV_TOOL_IMAGE) >/dev/null 2>&1 \
		|| { printf 'Image %s not found - building...\n' "$(DEV_TOOL_IMAGE)"; \
			$(MAKE) --no-print-directory tools-build; }

.PHONY: tools-clean
tools-clean: ## Remove the dev toolbox image
	@$(call log,removing $(DEV_TOOL_IMAGE))
	-docker image rm $(DEV_TOOL_IMAGE)

.PHONY: lint
lint: lint-shell lint-github-workflows ## Run every linter (shell scripts + GitHub workflows)

.PHONY: lint-shell
lint-shell: tools-ensure ## Run shellcheck over every shell script under bin/ and lib/
	@$(call log,shellcheck via $(DEV_TOOL_IMAGE))
	$(_DOCKER_RUN) shellcheck --rcfile dev/.shellcheckrc $(SHELL_SCRIPTS)

.PHONY: lint-github-workflows
lint-github-workflows: tools-ensure ## Lint workflow action format and shellcheck embedded scripts
	@$(call log,github workflow scan via $(DEV_TOOL_IMAGE))
	$(_DOCKER_RUN) python3 dev/bin/github_workflow_scan.py

.PHONY: test
test: tools-ensure ## Run the shellspec suite
	@$(call log,shellspec via $(DEV_TOOL_IMAGE))
	$(_DOCKER_RUN) shellspec

.PHONY: coverage
coverage: tools-ensure ## Run the suite under kcov, writing an HTML report to var/coverage/
	@$(call log,coverage via $(DEV_TOOL_IMAGE))
	@mkdir -p var/coverage
	$(_DOCKER_RUN_RW) shellspec --kcov --covdir var/coverage --kcov-options "$(KCOV_OPTIONS)"
	@$(call log,report at var/coverage/index.html)

.PHONY: fix-github-workflows
fix-github-workflows: tools-ensure ## Fix GitHub workflow action format in place
	@$(call log,fixing github workflow action format)
	$(_DOCKER_RUN_RW) python3 dev/bin/github_workflow_scan.py --fix-format

.PHONY: github-actions-outdated
github-actions-outdated: tools-ensure ## Report outdated GitHub actions (needs network)
	@$(call log,checking for outdated github actions)
	$(_DOCKER_RUN) python3 dev/bin/github_workflow_scan.py --report-outdated

.PHONY: github-actions-update
github-actions-update: tools-ensure ## Update GitHub actions to their latest version in place (needs network)
	@$(call log,updating github actions)
	$(_DOCKER_RUN_RW) python3 dev/bin/github_workflow_scan.py --update

.PHONY: check
check: lint test ## Run the linters and the test suite

.PHONY: help
help: ## Show available make targets
	@awk 'BEGIN {FS = ":.*?## "}; \
		/^[a-zA-Z_-]+:.*?## / { printf "  \033[36m%-24s\033[0m %s\n", $$1, $$2 }' \
		$(MAKEFILE_LIST)

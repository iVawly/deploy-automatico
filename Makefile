SHELL := /bin/bash
BATS ?= bats
SHELLCHECK ?= shellcheck
YAMLLINT ?= yamllint
HADOLINT_IMAGE ?= hadolint/hadolint:v2.15.1@sha256:32dac94127fd60b7b7e3fbfc65e1383b9b5e25c9bfd7b8536de7a539fe68a12d
ACTIONLINT_IMAGE ?= rhysd/actionlint:1.7.12@sha256:b1934ee5f1c509618f2508e6eb47ee0d3520686341fec936f3b79331f9315667
TRIVY_IMAGE ?= aquasec/trivy:0.76.1@sha256:790fd66d1697395d8693d1acaa1ea702406a20f109b6fc7bac8db623eca6c06c

.DEFAULT_GOAL := help
.PHONY: help test test-python lint lint-yaml lint-actions lint-docker build security check demo

help:
	@echo "make test          Bats + testes Python"
	@echo "make lint          ShellCheck + bash -n"
	@echo "make lint-yaml     yamllint"
	@echo "make lint-actions  actionlint (Docker)"
	@echo "make lint-docker   Hadolint (Docker)"
	@echo "make build         Constrói a imagem do demo-app"
	@echo "make security      Trivy filesystem (Docker)"
	@echo "make check         lint + lint-yaml + lint-actions + lint-docker + test"
	@echo "make demo          Mostra como rodar o demo local"

test: test-python
	$(BATS) tests

test-python:
	PYTHONPATH=apps/demo-app python -m unittest discover -s apps/demo-app/tests -v

lint:
	$(SHELLCHECK) scripts/ops-deploy scripts/*.sh scripts/server/*.sh local-demo/scripts/*.sh tests/shims/*
	while IFS= read -r -d '' file; do bash -n "$$file"; done < <(find scripts local-demo/scripts tests -type f \( -name '*.sh' -o -name 'ops-deploy' \) -print0)

lint-yaml:
	$(YAMLLINT) -c .yamllint .

lint-actions:
	docker run --rm -v "$(CURDIR):/repo" --workdir /repo $(ACTIONLINT_IMAGE) \
		.github/workflows/*.yml apps/demo-app/.github/workflows/*.yml

lint-docker:
	docker run --rm -i $(HADOLINT_IMAGE) < apps/demo-app/Dockerfile

build:
	docker build --build-arg VERSION=dev --build-arg REVISION=local -t demo-app:dev apps/demo-app

security:
	docker run --rm -v "$(CURDIR):/repo" --workdir /repo $(TRIVY_IMAGE) fs \
		--scanners vuln,secret --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 /repo

check: lint lint-yaml lint-actions lint-docker test

demo:
	@echo "Build and run the demo app locally:"
	@echo "  make build"
	@echo "  docker run --rm -p 8080:8080 -e APP_VERSION=dev demo-app:dev"
	@echo "  curl -s http://localhost:8080/health"

SHELL := /bin/bash

.PHONY: help init plan deploy wait fetch status ssh qr output rotate destroy clean-secrets check

help:
	@echo "Disposable Beijing VPS automation"
	@echo
	@echo "  make init           Initialize Terraform"
	@echo "  make plan           Review the Terraform plan"
	@echo "  make deploy         Create, bootstrap, validate, fetch, and display profiles"
	@echo "  make wait           Wait for bootstrap completion"
	@echo "  make fetch          Atomically retrieve the current client profiles"
	@echo "  make status         Show remote service health"
	@echo "  make ssh            Open an SSH session"
	@echo "  make qr             Display client profile QR codes"
	@echo "  make output         Show Terraform outputs"
	@echo "  make rotate         Replace the instance and retrieve fresh profiles"
	@echo "  make destroy        Interactively destroy managed infrastructure"
	@echo "  make clean-secrets  Delete locally retrieved profiles"
	@echo "  make check          Run static and local automated tests"

init:
	terraform -chdir=terraform init

plan: init
	terraform -chdir=terraform validate
	terraform -chdir=terraform plan

deploy: init
	terraform -chdir=terraform validate
	terraform -chdir=terraform apply -auto-approve
	./scripts/wait-ready.sh
	./scripts/fetch-config.sh
	./scripts/status.sh
	./scripts/qr.sh

wait:
	./scripts/wait-ready.sh

fetch:
	./scripts/fetch-config.sh

status:
	./scripts/status.sh

ssh:
	./scripts/ssh.sh

qr:
	./scripts/qr.sh

output:
	terraform -chdir=terraform output

rotate:
	./scripts/rotate.sh

destroy:
	terraform -chdir=terraform destroy

clean-secrets:
	rm -rf -- "$(CURDIR)/secrets"

check:
	./scripts/check.sh

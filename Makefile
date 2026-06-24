export ANSIBLE_CONFIG := $(CURDIR)/ansible/ansible.cfg

# Optional scoping: make apply ANSIBLE_LIMIT=core ANSIBLE_TAGS=harmony
ANSIBLE_LIMIT ?=
ANSIBLE_TAGS  ?=
_scope = $(if $(ANSIBLE_LIMIT),--limit $(ANSIBLE_LIMIT)) $(if $(ANSIBLE_TAGS),--tags $(ANSIBLE_TAGS))

# Terraform root selection (required): make provision TERRAFORM_DIRECTORY=unifi
TERRAFORM_DIRECTORY ?=
require_tf = test -n "$(TERRAFORM_DIRECTORY)" || { echo "TERRAFORM_DIRECTORY is required (e.g. proxmox, unifi)"; exit 1; }

.DEFAULT_GOAL := help
.PHONY: help install check apply provision provision-check

help:
	@echo "Usage: make <target> [ANSIBLE_LIMIT=...] [ANSIBLE_TAGS=...]"
	@echo
	@echo "Targets:"
	@echo "  check            dry-run site.yml (--check --diff)"
	@echo "  apply            apply site.yml"
	@echo "  provision        terraform apply (TERRAFORM_DIRECTORY selects the root)"
	@echo "  provision-check  terraform plan (TERRAFORM_DIRECTORY selects the root)"
	@echo "  install          install Ansible collections"
	@echo
	@echo "Hosts and groups (ANSIBLE_LIMIT):"
	@cd ansible && ansible-inventory --graph
	@echo
	@echo "Services (ANSIBLE_TAGS):"
	@cd ansible && ansible-playbook playbooks/site.yml --list-tags 2>/dev/null \
	  | grep -oE 'TASK TAGS: \[.*\]' | sed -E 's/TASK TAGS: \[(.*)\]/\1/; s/, /\n/g' \
	  | sort -u | sed 's/^/  /'
	@echo
	@echo "Terraform roots (TERRAFORM_DIRECTORY):"
	@ls -d terraform/*/ | sed -E 's#terraform/(.+)/#  \1#'

install:
	cd ansible && ansible-galaxy collection install -r requirements.yml

check:
	cd ansible && ansible-playbook playbooks/site.yml --check --diff $(_scope)

apply:
	cd ansible && ansible-playbook playbooks/site.yml $(_scope)

provision-check:
	@$(require_tf)
	cd terraform/$(TERRAFORM_DIRECTORY) && terraform init && terraform plan

provision:
	@$(require_tf)
	cd terraform/$(TERRAFORM_DIRECTORY) && terraform init && terraform apply

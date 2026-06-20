export ANSIBLE_CONFIG := $(CURDIR)/ansible/ansible.cfg

# Optional scoping: make apply LIMIT=core TAGS=harmony
LIMIT ?=
TAGS  ?=
_scope = $(if $(LIMIT),--limit $(LIMIT)) $(if $(TAGS),--tags $(TAGS))

.DEFAULT_GOAL := help
.PHONY: help install check apply provision provision-check

help:
	@echo "Usage: make <target> [LIMIT=...] [TAGS=...]"
	@echo
	@echo "Targets:"
	@echo "  check            dry-run site.yml (--check --diff)"
	@echo "  apply            apply site.yml"
	@echo "  provision        terraform apply (provision VMs on sol)"
	@echo "  provision-check  terraform plan"
	@echo "  install          install Ansible collections"
	@echo
	@echo "Hosts and groups (LIMIT):"
	@cd ansible && ansible-inventory --graph
	@echo
	@echo "Services (TAGS):"
	@cd ansible && ansible-playbook playbooks/site.yml --list-tags 2>/dev/null \
	  | grep -oE 'TASK TAGS: \[.*\]' | sed -E 's/TASK TAGS: \[(.*)\]/\1/; s/, /\n/g' \
	  | sort -u | sed 's/^/  /'

install:
	cd ansible && ansible-galaxy collection install -r requirements.yml

check:
	cd ansible && ansible-playbook playbooks/site.yml --check --diff $(_scope)

apply:
	cd ansible && ansible-playbook playbooks/site.yml $(_scope)

provision-check:
	cd terraform && terraform init && terraform plan

provision:
	cd terraform && terraform init && terraform apply

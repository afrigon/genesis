.DEFAULT_GOAL := help

export ANSIBLE_CONFIG := $(CURDIR)/ansible/ansible.cfg

.PHONY: help install vanguard vanguard-check sol sol-check

help:
	@echo "Targets:"
	@echo "  install         install ansible collections"
	@echo "  vanguard-check  dry-run the vanguard playbook (shows diff)"
	@echo "  vanguard        apply the vanguard playbook"
	@echo "  sol-check       dry-run the sol playbook (shows diff)"
	@echo "  sol             apply the sol playbook"

install:
	cd ansible && ansible-galaxy collection install -r requirements.yml

vanguard-check:
	cd ansible && ansible-playbook playbooks/vanguard.yml --check --diff

vanguard:
	cd ansible && ansible-playbook playbooks/vanguard.yml

sol-check:
	cd ansible && ansible-playbook playbooks/sol.yml --check --diff

sol:
	cd ansible && ansible-playbook playbooks/sol.yml

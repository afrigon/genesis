.DEFAULT_GOAL := help

export ANSIBLE_CONFIG := $(CURDIR)/ansible/ansible.cfg

.PHONY: help install vanguard vanguard-check

help:
	@echo "Targets:"
	@echo "  install         install ansible collections"
	@echo "  vanguard-check  dry-run the vanguard playbook (shows diff)"
	@echo "  vanguard        apply the vanguard playbook"

install:
	cd ansible && ansible-galaxy collection install -r requirements.yml

vanguard-check:
	cd ansible && ansible-playbook playbooks/vanguard.yml --check --diff

vanguard:
	cd ansible && ansible-playbook playbooks/vanguard.yml

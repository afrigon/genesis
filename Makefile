export ANSIBLE_CONFIG := $(CURDIR)/ansible/ansible.cfg

.PHONY: install vanguard vanguard-check sol sol-check sol-provision sol-provision-check

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

sol-provision-check:
	cd terraform && terraform init && terraform plan

sol-provision:
	cd terraform && terraform init && terraform apply

#!/bin/bash
# Install GitHub Actions Runner Controller
ansible-playbook -i ansible/inventory/management ansible/configurations/roles/github-runner.yml --tags github-runner,install

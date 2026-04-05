#!/bin/bash
# Install Management Apps for Kubernetes
ansible-playbook -i ansible/inventory/management ansible/configurations/management-apps.yml --tags management-apps,install
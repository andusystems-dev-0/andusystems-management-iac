#!/bin/bash
# Install Management Apps for Kubernetes
ansible-playbook -i ansible/inventory/management ansible/configurations/monitoring-apps.yml --tags monitoring-apps,install
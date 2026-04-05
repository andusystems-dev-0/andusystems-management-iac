#!/bin/bash
# Install ArgoCD for Kubernetes
ansible-playbook -i ansible/inventory/management ansible/configurations/roles/argocd.yml --tags argocd,install,cleanup
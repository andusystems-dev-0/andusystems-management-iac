#!/bin/bash
# Do a full redeploy of everything
ansible-playbook -i ansible/inventory/management ansible/configurations/deploy.yml --tags vms,kubernetes,argocd,apps,install -K
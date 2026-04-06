# Development Guide

## Prerequisites

### Required Tools

| Tool            | Minimum Version | Installation                                             |
|-----------------|-----------------|----------------------------------------------------------|
| Terraform       | >= 1.5.0        | [terraform.io](https://developer.hashicorp.com/terraform/install) |
| Ansible         | >= 2.15         | `pip install ansible`                                    |
| kubectl         | >= 1.31         | [kubernetes.io](https://kubernetes.io/docs/tasks/tools/) |
| Helm            | >= 3.x          | [helm.sh](https://helm.sh/docs/intro/install/)          |
| ArgoCD CLI      | >= 2.12         | [argo-proj.github.io](https://argo-cd.readthedocs.io/en/stable/cli_installation/) |
| Python          | >= 3.10         | Required by Ansible                                      |

### Ansible Collections

Install the required Ansible Galaxy collection:

```bash
ansible-galaxy collection install -r ansible/requirements.yml
```

This installs:
- `kubernetes.core` — Required for Kubernetes resource management tasks

### Access Requirements

- SSH access to the Proxmox hypervisors
- Proxmox API token with VM provisioning permissions
- SSH key pair for VM access (default user: `ubuntu`)
- Cloudflare API token (for DNS-01 certificate challenges)
- Ansible Vault password (for decrypting secrets)

## Local Development Setup

### 1. Clone the Repository

```bash
git clone <repository-url>
cd andusystems-management
```

### 2. Configure Secrets

Copy the vault example and populate it with your values:

```bash
cp ansible/inventory/management/group_vars/all/vault.example \
   ansible/inventory/management/group_vars/all/vault.yml
```

Edit `vault.yml` and fill in all `vault_` prefixed variables. Then encrypt it:

```bash
ansible-vault encrypt ansible/inventory/management/group_vars/all/vault.yml
```

### 3. Configure Terraform Variables

Create a `terraform.tfvars` file in each Terraform layer directory:

```bash
# Layer 1: VM provisioning
terraform/layers/layer-1-infrastructure/terraform.tfvars

# Layer 2: Helm applications
terraform/layers/layer-2-helmapps/terraform.tfvars
```

Key variables for Layer 1:

| Variable                    | Description                              |
|-----------------------------|------------------------------------------|
| `proxmox_endpoint`          | Proxmox API URL                          |
| `proxmox_api_token`         | Proxmox authentication token             |
| `proxmox_control_plane_node`| Proxmox node name for control plane VM   |
| `proxmox_worker_nodes`      | List of Proxmox node names for workers   |
| `control_plane_ip`          | Static IP for control plane              |
| `worker_ips`                | List of static IPs for workers           |
| `network_gateway`           | Default gateway IP                       |
| `ssh_public_key`            | SSH public key for VM access             |
| `kubeconfig_path`           | Local path to store kubeconfig           |

### 4. Initialize Terraform

```bash
cd terraform/layers/layer-1-infrastructure
terraform init

cd ../layer-2-helmapps
terraform init
```

## Deployment Commands

### Full Cluster Deployment

Provisions VMs, bootstraps Kubernetes, and deploys all services:

```bash
ansible-playbook -i ansible/inventory/management/hosts.yml \
  ansible/configurations/deploy.yml \
  --ask-vault-pass
```

### Application-Only Deployment

Deploys or updates applications on an existing cluster (skips VM and Kubernetes provisioning):

```bash
ansible-playbook -i ansible/inventory/management/hosts.yml \
  ansible/configurations/apps.yml \
  --ask-vault-pass
```

### ArgoCD-Only Deployment

Runs only the ArgoCD setup and cluster registration:

```bash
ansible-playbook -i ansible/inventory/management/hosts.yml \
  ansible/configurations/argocd.yml \
  --ask-vault-pass
```

### Running Individual Roles

To run a specific role (e.g., only Traefik):

```bash
ansible-playbook -i ansible/inventory/management/hosts.yml \
  ansible/configurations/apps.yml \
  --ask-vault-pass \
  --tags traefik
```

### Terraform Only

To run Terraform layers independently:

```bash
# Layer 1: Provision VMs
cd terraform/layers/layer-1-infrastructure
terraform plan
terraform apply

# Layer 2: Deploy MetalLB + ArgoCD
cd ../layer-2-helmapps
terraform plan
terraform apply
```

## Deployment Order

Services must be deployed in a specific order due to dependencies:

```
VMs → Kubernetes → ArgoCD + MetalLB → Longhorn → Forgejo
  → Traefik → Pangolin-Newt → Cert-Manager → Keycloak → Vault
  → Spoke Cluster Apps (Networking, Storage, Monitoring, FleetDock)
```

Critical ordering constraints:
- **Longhorn before Forgejo**: Forgejo requires persistent storage
- **Forgejo before Traefik**: ArgoCD applications reference Forgejo for Helm values
- **MetalLB before any LoadBalancer service**: Services cannot get external IPs without MetalLB
- **Cert-Manager after Traefik**: IngressRoutes need TLS certificates

## Playbook Structure

### deploy.yml

The master playbook that runs the full deployment. It imports roles in dependency order:

| Order | Role                       | Purpose                                  |
|-------|----------------------------|------------------------------------------|
| 1     | `vms`                      | Terraform VM provisioning + SSH setup    |
| 2     | `kubernetes`               | K8s v1.31 bootstrap with containerd      |
| 3     | `argocd`                   | ArgoCD + MetalLB + cluster registration  |
| 4     | `longhorn`                 | Distributed storage                      |
| 5     | `forgejo`                  | Git service + org/user/repo creation     |
| 6     | `traefik`                  | Ingress controller                       |
| 7     | `pangolin-newt`            | VPN connector                            |
| 8     | `cert-manager`             | TLS certificates                         |
| 9     | `keycloak`                 | SSO/OIDC                                 |
| 10    | `vault`                    | Secret management                        |
| 11    | `andusystems-networking`   | Networking cluster apps                  |
| 12    | `andusystems-storage`      | Storage cluster apps                     |
| 13    | `andusystems-monitoring`   | Monitoring cluster apps                  |
| 14    | `andusystems-fleetdock`    | FleetDock cluster apps                   |

### apps.yml

Application-only deployment that skips VM and Kubernetes provisioning. Useful for updating or adding services to an existing cluster. Includes additional roles:

- `kube-prometheus-stack` — Prometheus, Alertmanager, and exporters
- `loki` — Log aggregation
- `tempo` — Distributed tracing
- `alloy` — Unified observability collector
- `github-runner` — GitHub Actions Runner Controller
- `andusystems-slimerio` — Slimerio cluster registration

## Environment Variables

Ansible variables are sourced from Ansible Vault. The following categories of variables are used:

| Category              | Example Keys                                        |
|-----------------------|-----------------------------------------------------|
| Paths                 | `repo_root`, `tfvars_file`, `apps_dir`, `kubeconfig`|
| SSH                   | `ssh_user`, `ssh_key_path`                          |
| Network               | `control_plane_ip`, `worker_ips`, `metallb_ip_range`|
| Kubernetes            | `kubernetes_version`, `pod_network_cidr`            |
| ArgoCD                | `argocd_url`, `argocd_admin_password`               |
| DNS/TLS               | `cloudflare_api_token`                              |
| Forgejo               | `forgejo_url`, `forgejo_admin_password`              |
| Keycloak              | `keycloak_url`, `keycloak_admin_user`               |
| Vault                 | `vault_url`                                         |
| VPN                   | `newt_id`, `newt_secret`, `newt_endpoint`           |
| Monitoring            | `minio_access_key`, `minio_secret_key`              |
| CI/CD                 | `github_runner_pat`                                 |
| Per-Cluster Traefik   | `monitoring_traefik_server_ip`, etc.                |
| Per-Cluster Kubeconfig| `monitoring_kubeconfig`, `fleetdock_kubeconfig`, etc.|

## Ansible Configuration

The `ansible.cfg` file sets:

```ini
host_key_checking = False    # Skip SSH host key verification
log_path = ansible.log       # Log output to file
become_ask_pass = false      # Do not prompt for sudo password
```

## Troubleshooting

### ArgoCD Sync Issues

If an ArgoCD application fails to sync, check the ArgoCD dashboard or CLI:

```bash
argocd app list
argocd app get <app-name>
argocd app sync <app-name>
```

### Kubernetes Node Issues

Verify node status and check for resource pressure:

```bash
kubectl get nodes
kubectl describe node <node-name>
```

### Longhorn Storage

Check Longhorn volume health:

```bash
kubectl -n longhorn-system get volumes.longhorn.io
kubectl -n longhorn-system get nodes.longhorn.io
```

### Pod OOM Issues

If pods are getting OOMKilled (e.g., Alloy), check and adjust resource limits in the relevant `apps/<service>/values.yml` file, then re-sync via ArgoCD.

### Cert-Manager

Verify certificate issuance:

```bash
kubectl get certificates -A
kubectl get clusterissuers
kubectl describe certificate <cert-name> -n <namespace>
```

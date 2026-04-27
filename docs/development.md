# Development Guide

## Prerequisites

### Required Tools

| Tool | Minimum Version | Installation |
|---|---|---|
| Terraform | >= 1.5.0 | [developer.hashicorp.com/terraform/install](https://developer.hashicorp.com/terraform/install) |
| Ansible | >= 2.15 | `pip install ansible` |
| kubectl | >= 1.31 | [kubernetes.io/docs/tasks/tools](https://kubernetes.io/docs/tasks/tools/) |
| Helm | >= 3.x | [helm.sh/docs/intro/install](https://helm.sh/docs/intro/install/) |
| ArgoCD CLI | >= 2.12 | [argo-cd.readthedocs.io/en/stable/cli_installation](https://argo-cd.readthedocs.io/en/stable/cli_installation/) |
| Python | >= 3.10 | Required by Ansible |

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
- GitHub Personal Access Token (for Actions Runner Controller, if deploying CI runners)

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

Edit `vault.yml` and fill in all required variables. Then encrypt it:

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

| Variable | Description |
|---|---|
| `proxmox_endpoint` | Proxmox API URL |
| `proxmox_api_token` | Proxmox authentication token |
| `proxmox_control_plane_node` | Proxmox node name for control plane VM |
| `proxmox_worker_nodes` | List of Proxmox node names for workers |
| `control_plane_ip` | Static IP for control plane |
| `worker_ips` | List of static IPs for workers |
| `network_gateway` | Default gateway IP |
| `ssh_public_key` | SSH public key for VM access |
| `kubeconfig_path` | Local path to store kubeconfig |

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

### Helper Scripts

Shell scripts in `scripts/` provide shortcuts for common partial deployments:

| Script | Purpose |
|---|---|
| `scripts/vms.sh` | Deploy VMs only |
| `scripts/kubernetes.sh` | Deploy Kubernetes only |
| `scripts/argocd.sh` | Bootstrap ArgoCD |
| `scripts/apps.sh` | Deploy all applications |
| `scripts/management-apps.sh` | Deploy management cluster apps only |
| `scripts/monitoring-apps.sh` | Deploy monitoring cluster apps only |
| `scripts/github-runner.sh` | Deploy GitHub Actions runners |
| `scripts/redeploy.sh` | Full redeployment from scratch |

## Deployment Order

Services must be deployed in a specific order due to dependencies:

```
VMs → Kubernetes → ArgoCD + MetalLB → Longhorn → Forgejo
  → Traefik → Pangolin-Newt → Cert-Manager → Keycloak → Vault
  → Observability (Prometheus, Loki, Tempo, Alloy)
  → GitHub Runner (ARC)
  → Spoke Cluster Apps (Networking, Storage, Monitoring, Portfolio, Slimerio)
```

Critical ordering constraints:

- **Longhorn before Forgejo**: Forgejo requires a persistent volume for Git repository data
- **Forgejo before Traefik**: ArgoCD applications reference Forgejo as the `$values` source for Helm values
- **MetalLB before any LoadBalancer service**: Services cannot get external IPs without MetalLB
- **Cert-Manager after Traefik**: IngressRoutes need TLS certificates to be issued

## Playbook Structure

### deploy.yml

The master playbook that runs the full deployment. It imports roles in dependency order:

| Order | Role | Purpose |
|---|---|---|
| 1 | `vms` | Terraform VM provisioning + SSH setup |
| 2 | `kubernetes` | K8s v1.31 bootstrap with containerd |
| 3 | `argocd` | ArgoCD + MetalLB + cluster registration |
| 4 | `longhorn` | Distributed storage |
| 5 | `forgejo` | Git service + org/user/repo creation |
| 6 | `traefik` | Ingress controller |
| 7 | `pangolin-newt` | VPN connector |
| 8 | `cert-manager` | TLS certificates |
| 9 | `keycloak` | SSO/OIDC |
| 10 | `vault` | Secret management |
| 11 | `andusystems-networking` | Networking cluster apps |
| 12 | `andusystems-storage` | Storage cluster apps |
| 13 | `andusystems-monitoring` | Monitoring cluster apps |
| 14 | `andusystems-portfolio` | Portfolio cluster apps |

### apps.yml

Application-only deployment that skips VM and Kubernetes provisioning. Useful for updating or adding services to an existing cluster. Includes additional roles beyond `deploy.yml`:

- `kube-prometheus-stack` — Prometheus, Alertmanager, and exporters
- `loki` — Log aggregation
- `tempo` — Distributed tracing
- `alloy` — Unified observability collector
- `cluster-status` — Cluster health status application
- `github-runner` — GitHub Actions Runner Controller
- `andusystems-slimerio` — Slimerio cluster registration
- `andusystems-portfolio` — Portfolio cluster registration

### argocd.yml

Minimal playbook focused on ArgoCD bootstrap:

1. Terraform apply (Layer 2) to install MetalLB and ArgoCD Helm charts
2. Apply MetalLB manifest (IPAddressPool + L2Advertisement)
3. Wait for ArgoCD server pod and service readiness
4. Patch ArgoCD service to LoadBalancer type for initial access
5. Login with admin credentials
6. Register Git repositories (Forgejo, Slimerio)
7. Register spoke clusters via kubeconfig

## Environment Variables

Ansible variables are sourced from Ansible Vault. The following categories of variables are used:

| Category | Example Keys |
|---|---|
| Paths | `repo_root`, `tfvars_file`, `apps_dir`, `kubeconfig` |
| SSH | `ssh_user`, `ssh_key_path` |
| Network | `control_plane_ip`, `worker_ips`, `metallb_ip_range` |
| Kubernetes | `kubernetes_version`, `pod_network_cidr` |
| ArgoCD | `argocd_url`, `argocd_admin_password`, `argocd_server_ip` |
| DNS/TLS | `cloudflare_api_token`, `letsencrypt_email` |
| Forgejo | `forgejo_url`, `forgejo_admin_password` |
| Keycloak | `keycloak_url`, `keycloak_admin_user`, `keycloak_admin_password` |
| Vault | `vault_url` |
| VPN | `newt_id`, `newt_secret`, `pangolin_endpoint` |
| Monitoring | `minio_root_user`, `minio_root_password` |
| OIDC | `grafana_oidc_client_secret` |
| CI/CD | `github_runner_pat`, `github_runner_repo` |
| Per-Cluster Traefik IPs | `monitoring_traefik_server_ip`, `storage_traefik_server_ip`, etc. |
| Per-Cluster Kubeconfigs | `monitoring_kubeconfig`, `storage_kubeconfig`, etc. |

## Ansible Configuration

The `ansible.cfg` file sets:

```ini
host_key_checking = False    # Skip SSH host key verification
log_path = ansible.log       # Log output to file
become_ask_pass = false      # Do not prompt for sudo password
```

## Adding a New Application

To add a new application to the management cluster:

1. **Create the app directory** under `apps/<app-name>/` with:
   - `manifest.yml` — ArgoCD Application resource referencing the Helm chart
   - `values.yml` — Helm values override file

2. **Create an Ansible role** under `ansible/configurations/roles/<app-name>/`:
   - `defaults/main.yml` — Default variables
   - `tasks/main.yml` — Entry point (typically includes `install.yml`)
   - `tasks/install.yml` — kubectl apply of the manifest and any additional resources

3. **Create a playbook wrapper** at `ansible/configurations/roles/<app-name>.yml` that targets `localhost` and includes the role.

4. **Add to a deployment playbook** — Import the role in `deploy.yml` or `apps.yml` at the correct position respecting dependency order.

5. **Push values to Forgejo** — If the ArgoCD Application uses `$values` referencing the management repository, ensure the values file is committed and pushed to the Forgejo instance.

## Adding a New Spoke Cluster

To register a new spoke cluster with the management ArgoCD:

1. **Obtain the kubeconfig** for the new cluster and store it as an Ansible Vault variable.

2. **Register the cluster** in the ArgoCD role (`ansible/configurations/roles/argocd/tasks/install.yml`) by adding a cluster registration command with the appropriate label (`argocd.argoproj.io/secret-type=cluster`).

3. **Create an app manifest directory** under `apps/andusystems-<cluster-name>/` containing the ArgoCD Application manifests for each service to deploy.

4. **Create an Ansible role** under `ansible/configurations/roles/andusystems-<cluster-name>/` with tasks to apply the manifests.

5. **Add to deployment playbooks** — Import the new role in `deploy.yml` and/or `apps.yml`.

## Traefik Configuration

The Traefik ingress controller is configured via `apps/traefik/values.yml`. The ArgoCD Application manifest (`apps/traefik/manifest.yml`) deploys Traefik using Helm chart v32.1.1 (image v3.6.7) into the `traefik` namespace, with a MetalLB-backed LoadBalancer service.

### Providers

| Provider | Setting | Value | Purpose |
|---|---|---|---|
| `kubernetesIngress` | `publishedService.enabled` | `true` | Populates Ingress status with the LB address |
| `kubernetesCRD` | `enabled` | `true` | Enables Traefik IngressRoute CRDs |
| `kubernetesCRD` | `allowCrossNamespace` | `true` | Routes can reference services in other namespaces |
| `kubernetesCRD` | `allowExternalNameServices` | `true` | Routes can target ExternalName services |

### Entrypoints (Ports)

| Entrypoint | Container Port | Exposed Port | Protocol | Notes |
|---|---|---|---|---|
| `web` | 8000 | 80 | TCP | HTTP traffic |
| `websecure` | 8443 | 443 | TCP | HTTPS traffic |

HTTP-to-HTTPS redirection is commented out until TLS is fully configured. To enable it, uncomment the `redirections` block under the `web` entrypoint.

### RBAC

RBAC is enabled cluster-wide (`namespaced: false`) to support cross-namespace routing. An additional `ClusterRole` and `ClusterRoleBinding` (`traefik-configmap-access`) are created via `extraObjects` to grant the `management-traefik` service account read access to ConfigMaps. This resolves a "configmaps forbidden" error that occurs with the default Helm RBAC.

### Additional Arguments

The following CLI arguments are passed to Traefik via `additionalArguments`:

- `--accesslog=true` — Enables access logging for debugging requests
- `--log.level=DEBUG` — Sets log verbosity to DEBUG

These should be adjusted for production (e.g., set log level to `WARN` or `ERROR`).

### Dashboard

The Traefik dashboard and API are commented out in the values file. To enable the dashboard, uncomment the `ingressRoute.dashboard` and `api` sections and configure appropriate host matching rules and TLS settings.

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

### MetalLB

Verify IP pool and address assignment:

```bash
kubectl -n metallb get ipaddresspools
kubectl get svc -A | grep LoadBalancer
```

### Forgejo

If ArgoCD cannot sync applications, verify Forgejo is running and accessible from within the cluster:

```bash
kubectl -n forgejo get pods
kubectl -n forgejo get svc
```

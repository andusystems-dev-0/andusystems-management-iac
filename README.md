# andusystems-management

> Infrastructure-as-code hub for the andusystems homelab — provisions and governs a management Kubernetes cluster and all downstream spoke clusters via ArgoCD.

## Purpose

This repository defines the complete lifecycle of the management Kubernetes cluster: VM provisioning on Proxmox with Terraform, cluster bootstrap with Ansible, and GitOps-driven application delivery via ArgoCD. The management cluster acts as the hub in a hub-spoke model, orchestrating deployments to all other clusters in the homelab (monitoring, storage, networking, portfolio, and application clusters). It also runs shared internal services including a self-hosted Git forge (Forgejo), SSO provider (Keycloak), secrets manager (Vault), and a full LGTM observability stack.

## At a glance

| Field | Value |
|---|---|
| Type | IaC cluster |
| Network | Dedicated management VLAN on a /24 subnet |
| Role | hub |
| Primary stack | Terraform + Ansible + ArgoCD + Helm |
| Deployed by | self-bootstrap |
| Status | production |

## Components

| Component | Purpose | Namespace |
|---|---|---|
| MetalLB | kubernetes load balancer — provides external IPs for services | `metallb` |
| ArgoCD | GitOps hub — manages all cluster and spoke deployments | `argocd` |
| Traefik | Ingress controller using IngressRoute CRDs | `traefik` |
| cert-manager | Automated TLS via Let's Encrypt DNS-01 (Cloudflare) | `cert-manager` |
| Longhorn | Distributed block storage; default StorageClass | `longhorn-system` |
| Forgejo | Self-hosted Git forge and Helm values source for ArgoCD | `forgejo` |
| Keycloak | SSO/OIDC provider (Grafana SSO integration) | `keycloak` |
| HashiCorp Vault | Secrets management with file-based storage | `vault` |
| kube-prometheus-stack | Cluster metrics, Alertmanager, and exporters | `prometheus` |
| Loki | Log aggregation with MinIO S3 backend | `loki` |
| Tempo | Distributed tracing with MinIO S3 backend | `tempo` |
| Alloy (k8s-monitoring) | Unified observability collector | `alloy` |
| Pangolin-Newt | VPN connector for administrative access | `newt` |
| GitHub ARC | Self-hosted GitHub Actions runner controller | `arc-systems` / `arc-runners` |
| cluster-status | Cluster health status application | `cluster-status` |

## Architecture

```
Proxmox Hypervisors
└── Management Cluster (dedicated /24 VLAN)
    ├── Ingress layer
    │   MetalLB (L2) ──► Traefik IngressRoutes ──► TLS termination (cert-manager)
    │
    ├── GitOps (ArgoCD hub)
    │   └── manages spoke clusters ──────────────────────────────────────────┐
    │                                                                         │
    │   Spoke Clusters (each on its own VLAN)                                │
    │   ├── Monitoring   — Grafana, Prometheus, Loki, Tempo, Alloy           │◄──┘
    │   ├── Storage      — MinIO (S3), Longhorn
    │   ├── Networking   — PiHole DNS
    │   ├── Portfolio    — web application cluster
    │   └── Slimerio     — application workloads
    │
    ├── Internal services
    │   Forgejo (Git) · Keycloak (SSO) · Vault (secrets)
    │
    └── Observability stack
        Prometheus · Loki · Tempo · Alloy (collector)
```

The diagram shows the management cluster as the control plane for all homelab infrastructure. Each spoke cluster receives Traefik, cert-manager, Pangolin-Newt, Longhorn, and an Alloy collector that ships metrics, logs, and traces back to the management observability stack. See [docs/architecture.md](docs/architecture.md) for the full component diagram and data flows.

## Quick start

### Prerequisites

| Tool | Version | Purpose |
|---|---|---|
| Terraform | >= 1.5.0 | VM provisioning on Proxmox |
| Ansible | >= 2.15 | Configuration management |
| kubectl | >= 1.31 | Kubernetes CLI |
| Helm | >= 3.x | Helm chart management |
| ArgoCD CLI | >= 2.12 | ArgoCD management and cluster registration |
| Python | >= 3.10 | Required by Ansible |

### Deploy / run

```bash
# Install required Ansible collections
ansible-galaxy collection install -r ansible/requirements.yml

# Copy the vault template and fill in secrets, then encrypt
cp ansible/inventory/management/group_vars/all/vault.example \
   ansible/inventory/management/group_vars/all/vault.yml
# edit vault.yml with real values, then:
ansible-vault encrypt ansible/inventory/management/group_vars/all/vault.yml

# Full deployment: VMs → Kubernetes → ArgoCD → all services
ansible-playbook -i ansible/inventory/management/hosts.yml \
  ansible/configurations/deploy.yml --ask-vault-pass

# Applications only (on an existing cluster, skips VM and K8s provisioning)
ansible-playbook -i ansible/inventory/management/hosts.yml \
  ansible/configurations/apps.yml --ask-vault-pass
```

See [docs/development.md](docs/development.md) for Terraform-only, role-targeted, and script-based deployment options.

## Configuration

| Key | Required | Description |
|---|---|---|
| `proxmox_endpoint` | Yes | Proxmox API URL |
| `proxmox_api_token` | Yes | Proxmox authentication token |
| `control_plane_ip` | Yes | Static IP for the control plane VM |
| `worker_ips` | Yes | List of static IPs for worker VMs |
| `network_gateway` | Yes | Default gateway for the management VLAN |
| `ssh_public_key` | Yes | SSH public key for VM cloud-init |
| `metallb_ip_range` | Yes | IP range for MetalLB load balancer pool |
| `argocd_url` | Yes | ArgoCD ingress hostname |
| `argocd_admin_password` | Yes | ArgoCD admin password |
| `cloudflare_api_token` | Yes | Cloudflare token for DNS-01 TLS challenges |
| `forgejo_admin_password` | Yes | Forgejo admin password |
| `keycloak_admin_user` | Yes | Keycloak admin username |
| `keycloak_admin_password` | Yes | Keycloak admin password |
| `vault_url` | Yes | HashiCorp Vault ingress hostname |
| `minio_root_user` | Yes | MinIO root username (Loki/Tempo S3 backend) |
| `minio_root_password` | Yes | MinIO root password |
| `pangolin_endpoint` | Yes | Pangolin VPN server endpoint |
| `newt_id` / `newt_secret` | Yes | Pangolin-Newt connector credentials |
| `github_runner_pat` | Optional | GitHub PAT for Actions Runner Controller |
| `grafana_oidc_client_secret` | Optional | OIDC client secret for Keycloak-Grafana SSO |

All secrets are encrypted in `ansible/inventory/management/group_vars/all/vault.yml` using Ansible Vault. Copy `vault.example` to see required keys. Never commit unencrypted secrets.

## Repository layout

```
.
├── terraform/
│   └── layers/
│       ├── layer-1-infrastructure/   # Proxmox VM provisioning (bpg/proxmox provider)
│       └── layer-2-helmapps/         # MetalLB + ArgoCD Helm releases
├── ansible/
│   ├── ansible.cfg                   # Ansible settings (host_key_checking, log_path)
│   ├── requirements.yml              # Ansible Galaxy collections (kubernetes.core)
│   ├── configurations/
│   │   ├── deploy.yml                # Full stack deployment playbook
│   │   ├── apps.yml                  # Application-only deployment playbook
│   │   ├── argocd.yml                # ArgoCD bootstrap playbook
│   │   └── roles/                    # Per-component Ansible roles
│   └── inventory/
│       └── management/
│           ├── hosts.yml             # Cluster node inventory
│           └── group_vars/all/       # Variables and vault secrets
├── apps/                             # ArgoCD Application manifests and Helm values
│   ├── argocd/ metallb/ traefik/     # Core networking and GitOps
│   ├── cert-manager/ longhorn/       # TLS management and storage
│   ├── forgejo/ keycloak/ vault/     # Internal services
│   ├── prometheus/ loki/ tempo/ alloy/ # Observability stack
│   ├── pangolin-newt/ github-runner/ # VPN and CI runners
│   ├── cluster-status/               # Cluster health application
│   └── andusystems-*/                # Spoke cluster application sets
├── scripts/                          # Deployment helper shell scripts
└── docs/                             # Architecture and development guides
```

## Related repos

| Repo | Relation |
|---|---|
| andusystems-monitoring | spoke — observability cluster (Grafana, Prometheus, Loki, Tempo) |
| andusystems-storage | spoke — storage cluster (MinIO S3-compatible object store) |
| andusystems-networking | spoke — networking cluster (PiHole DNS) |
| andusystems-portfolio | spoke — portfolio web application cluster |
| andusystems-slimerio | spoke — application workloads cluster |

## Further documentation

- [Architecture](docs/architecture.md) — component diagrams, data flows, design decisions
- [Development](docs/development.md) — local setup, build, deploy, troubleshoot
- [Changelog](CHANGELOG.md) — release history

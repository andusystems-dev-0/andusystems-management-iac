# andusystems-management

Infrastructure-as-Code for the management Kubernetes cluster, serving as the central control plane for a multi-cluster homelab environment running on Proxmox.

## Overview

This repository provisions and configures a Kubernetes cluster dedicated to management and internal services. It uses a layered approach:

1. **Terraform** provisions virtual machines on Proxmox with cloud-init, static IPs, and VLAN tagging.
2. **Ansible** bootstraps Kubernetes, installs core services, and deploys applications via ArgoCD.
3. **ArgoCD** manages Helm-based application manifests using a hub-spoke model to govern multiple downstream clusters.

The management cluster acts as the **hub** — running the primary ArgoCD instance that orchestrates deployments across all other clusters (monitoring, storage, networking, and application clusters).

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                   Proxmox Hosts                     │
│  ┌───────────────────────────────────────────────┐  │
│  │      Management Cluster (Dedicated VLAN)      │  │
│  │                                               │  │
│  │  ┌─────────┐  ┌────────┐  ┌──────────────┐   │  │
│  │  │ ArgoCD  │  │Traefik │  │ Cert-Manager │   │  │
│  │  │  (Hub)  │  │(Ingress)│  │  (TLS/DNS)  │   │  │
│  │  └────┬────┘  └────────┘  └──────────────┘   │  │
│  │       │                                       │  │
│  │  ┌────┴──────────────────────────────────┐    │  │
│  │  │  Spoke Clusters (via ArgoCD)          │    │  │
│  │  │  • Monitoring  • Storage              │    │  │
│  │  │  • Networking  • FleetDock            │    │  │
│  │  │  • Slimerio    • Portfolio            │    │  │
│  │  └───────────────────────────────────────┘    │  │
│  │                                               │  │
│  │  ┌──────────┐ ┌────────┐ ┌───────────────┐   │  │
│  │  │ Forgejo  │ │Keycloak│ │  Vault        │   │  │
│  │  │  (Git)   │ │ (SSO)  │ │  (Secrets)    │   │  │
│  │  └──────────┘ └────────┘ └───────────────┘   │  │
│  │                                               │  │
│  │  ┌──────────┐ ┌────────┐ ┌───────────────┐   │  │
│  │  │Prometheus│ │  Loki  │ │    Tempo      │   │  │
│  │  │(Metrics) │ │ (Logs) │ │  (Traces)     │   │  │
│  │  └──────────┘ └────────┘ └───────────────┘   │  │
│  └───────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

For detailed architecture documentation, see [docs/architecture.md](docs/architecture.md).

## Quick Start

### Prerequisites

| Tool       | Version   | Purpose                        |
|------------|-----------|--------------------------------|
| Terraform  | >= 1.5.0  | VM provisioning on Proxmox     |
| Ansible    | >= 2.15   | Configuration management       |
| kubectl    | >= 1.31   | Kubernetes CLI                 |
| Helm       | >= 3.x    | Helm chart management          |
| ArgoCD CLI | >= 2.12   | ArgoCD management              |
| Python     | >= 3.10   | Required by Ansible            |

### Deployment

The full deployment is orchestrated through Ansible playbooks that call Terraform and apply Kubernetes manifests.

```bash
# 1. Install required Ansible collections
ansible-galaxy collection install -r ansible/requirements.yml

# 2. Provision VMs and bootstrap Kubernetes
ansible-playbook -i ansible/inventory/management/hosts.yml \
  ansible/configurations/deploy.yml \
  --ask-vault-pass

# 3. Deploy applications (after initial cluster setup)
ansible-playbook -i ansible/inventory/management/hosts.yml \
  ansible/configurations/apps.yml \
  --ask-vault-pass
```

The `deploy.yml` playbook executes the full stack in order:

1. **VMs** — Terraform provisions Proxmox VMs with cloud-init
2. **Kubernetes** — Bootstraps K8s v1.31 with containerd and Flannel CNI
3. **ArgoCD** — Installs ArgoCD + MetalLB via Helm, registers spoke clusters
4. **Longhorn** — Distributed storage (required before Forgejo)
5. **Forgejo** — Git service (ArgoCD values source for all clusters)
6. **Traefik** — Ingress controller with IngressRoute CRDs
7. **Pangolin-Newt** — VPN connectivity
8. **Cert-Manager** — TLS via Let's Encrypt (DNS-01 with Cloudflare)
9. **Keycloak** — SSO/OIDC provider
10. **Vault** — Secret management
11. **Spoke Clusters** — Networking, Storage, Monitoring, Portfolio, and additional app clusters

### Configuration

All sensitive configuration is managed through Ansible Vault. See the vault example template:

```
ansible/inventory/management/group_vars/all/vault.example
```

Key configuration variables:

| Variable Category      | Description                                          |
|------------------------|------------------------------------------------------|
| `ssh_*`                | SSH user, key paths for VM access                    |
| `control_plane_ip`     | Static IP for the control plane VM                   |
| `worker_ips`           | Static IPs for worker VMs                            |
| `kubernetes_version`   | Kubernetes version (currently 1.31)                  |
| `pod_network_cidr`     | Pod network CIDR for Flannel CNI                     |
| `metallb_ip_range`     | IP range for MetalLB load balancer pool              |
| `argocd_*`             | ArgoCD credentials and URL                           |
| `cloudflare_api_token` | Cloudflare token for DNS-01 challenges               |
| `forgejo_*`            | Forgejo admin credentials and URL                    |
| `keycloak_*`           | Keycloak admin credentials and URL                   |
| `vault_*`              | HashiCorp Vault URL and credentials                  |
| `github_runner_pat`    | GitHub Personal Access Token for self-hosted runners |

## Repository Structure

```
├── terraform/
│   └── layers/
│       ├── layer-1-infrastructure/   # Proxmox VM provisioning
│       └── layer-2-helmapps/         # MetalLB + ArgoCD Helm releases
├── ansible/
│   ├── ansible.cfg                   # Ansible settings
│   ├── configurations/
│   │   ├── deploy.yml                # Full deployment playbook
│   │   ├── apps.yml                  # Application-only deployment
│   │   ├── argocd.yml                # ArgoCD-specific playbook
│   │   └── roles/                    # Ansible roles for each component
│   └── inventory/
│       └── management/
│           ├── hosts.yml             # Cluster node inventory
│           └── group_vars/all/       # Variables and vault
├── apps/                             # ArgoCD Application manifests + Helm values
│   ├── argocd/                       # ArgoCD server
│   ├── traefik/                      # Ingress controller
│   ├── metallb/                      # Load balancer
│   ├── cert-manager/                 # TLS certificate management
│   ├── longhorn/                     # Distributed storage
│   ├── vault/                        # Secret management
│   ├── keycloak/                     # SSO/OIDC
│   ├── forgejo/                      # Git service
│   ├── prometheus/                   # Metrics (kube-prometheus-stack)
│   ├── loki/                         # Log aggregation
│   ├── tempo/                        # Distributed tracing
│   ├── alloy/                        # Unified observability collector
│   ├── pangolin-newt/                # VPN connector
│   ├── github-runner/                # GitHub Actions runner controller
│   ├── andusystems-monitoring/       # Monitoring cluster apps
│   ├── andusystems-storage/          # Storage cluster apps
│   ├── andusystems-networking/       # Networking cluster apps
│   ├── andusystems-fleetdock/        # FleetDock cluster apps
│   ├── andusystems-slimerio/         # Slimerio cluster apps
│   └── andusystems-portfolio/        # Portfolio cluster apps
├── scripts/                          # Deployment helper scripts
└── docs/                             # Project documentation
```

## Spoke Clusters

The management cluster's ArgoCD instance deploys applications to these downstream clusters:

| Cluster       | Purpose                                | Key Applications                                       |
|---------------|----------------------------------------|--------------------------------------------------------|
| Monitoring    | Centralized observability              | Grafana, Prometheus, Loki, Tempo, Alloy, Homepage      |
| Storage       | Persistent storage services            | MinIO (S3), Longhorn, Prometheus, Loki, Tempo          |
| Networking    | Network services                       | PiHole (DNS), Longhorn, Prometheus, Loki               |
| FleetDock     | Game server management                 | Longhorn, Prometheus, Loki, Tempo                      |
| Slimerio      | Application cluster                    | Slimerio app, Longhorn, Prometheus, Loki               |
| Portfolio     | Portfolio application cluster          | Portfolio app, Longhorn, Prometheus, Loki               |

Each spoke cluster also receives its own Traefik ingress controller, cert-manager instance, Pangolin-Newt VPN connector, and full observability stack (Prometheus, Loki, Tempo, Alloy).

## Technology Stack

| Component        | Technology                                |
|------------------|-------------------------------------------|
| Hypervisor       | Proxmox VE                                |
| OS               | Ubuntu Noble 24.04 LTS                    |
| Container Runtime| containerd                                |
| Kubernetes       | v1.31 (kubeadm)                           |
| CNI              | Flannel                                   |
| GitOps           | ArgoCD                                    |
| Ingress          | Traefik (IngressRoute CRDs)               |
| Load Balancer    | MetalLB (L2 mode)                         |
| TLS              | cert-manager + Let's Encrypt (Cloudflare) |
| Storage          | Longhorn (block), MinIO (object/S3)       |
| Git              | Forgejo (self-hosted)                     |
| SSO              | Keycloak (OIDC)                           |
| Secrets          | HashiCorp Vault                           |
| Observability    | Prometheus, Loki, Tempo, Alloy, Grafana   |
| CI/CD Runners    | GitHub Actions Runner Controller (ARC)    |
| VPN              | Pangolin-Newt                             |

## Further Documentation

- [Architecture](docs/architecture.md) — Component diagram, data flows, design decisions
- [Development Guide](docs/development.md) — Prerequisites, local setup, deployment commands
- [Changelog](CHANGELOG.md) — Release history

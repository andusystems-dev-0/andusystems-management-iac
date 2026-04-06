# Architecture

## Overview

The andusystems-management repository implements a hub-spoke infrastructure model. A central **management cluster** runs ArgoCD as the single source of truth for GitOps deployments across multiple Kubernetes clusters, each isolated on its own VLAN.

All infrastructure is hosted on Proxmox bare-metal servers connected through a managed router handling inter-VLAN routing.

## Component Diagram

```
┌──────────────────────────────────────────────────────────────────────┐
│                        Proxmox Hypervisors                          │
│                                                                      │
│  ┌────────────────── Management Cluster (Dedicated VLAN) ─────────┐  │
│  │                                                                 │  │
│  │  ┌─────────────────────────────────────────────────────────┐    │  │
│  │  │                  Ingress Layer                          │    │  │
│  │  │  MetalLB (L2) ──► Traefik (IngressRoute CRDs)         │    │  │
│  │  │                    ├── TLS termination                  │    │  │
│  │  │                    └── HTTP → HTTPS redirect            │    │  │
│  │  └─────────────────────────────────────────────────────────┘    │  │
│  │                                                                 │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │  │
│  │  │   ArgoCD     │  │  Cert-Manager│  │  Pangolin-Newt       │  │  │
│  │  │  (GitOps Hub)│  │  (DNS-01 via │  │  (VPN Connector)     │  │  │
│  │  │              │  │  Cloudflare)  │  │                      │  │  │
│  │  └──────┬───────┘  └──────────────┘  └──────────────────────┘  │  │
│  │         │                                                       │  │
│  │         │  Manages deployments to:                              │  │
│  │         │                                                       │  │
│  │  ┌──────┴──────────────────────────────────────────────────┐   │  │
│  │  │              Spoke Cluster Targets                       │   │  │
│  │  │  ┌────────────┐ ┌─────────┐ ┌────────────┐ ┌────────┐  │   │  │
│  │  │  │ Monitoring │ │ Storage │ │ Networking │ │FleetDock│  │   │  │
│  │  │  └────────────┘ └─────────┘ └────────────┘ └────────┘  │   │  │
│  │  └─────────────────────────────────────────────────────────┘   │  │
│  │                                                                 │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │  │
│  │  │   Forgejo     │  │  Keycloak    │  │  HashiCorp Vault     │  │  │
│  │  │  (Git/Values) │  │  (SSO/OIDC)  │  │  (Secrets)           │  │  │
│  │  └──────────────┘  └──────────────┘  └──────────────────────┘  │  │
│  │                                                                 │  │
│  │  ┌──────────── Observability Stack ─────────────────────────┐  │  │
│  │  │  Prometheus ◄── Alloy (collector) ──► Loki    Tempo      │  │  │
│  │  │  (metrics)      (push from spokes)    (logs)  (traces)   │  │  │
│  │  └──────────────────────────────────────────────────────────┘  │  │
│  │                                                                 │  │
│  │  ┌──────────────┐  ┌──────────────────────────────────────┐    │  │
│  │  │  Longhorn     │  │  GitHub Actions Runner Controller   │    │  │
│  │  │  (Storage)    │  │  (Self-hosted CI/CD runners)        │    │  │
│  │  └──────────────┘  └──────────────────────────────────────┘    │  │
│  └─────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────┘
```

## Infrastructure Layers

Deployment is organized into two Terraform layers, followed by Ansible-driven service installation.

### Layer 1: VM Provisioning

Terraform provisions virtual machines on Proxmox using the `bpg/proxmox` provider:

- **Control plane VM**: Higher resource allocation (4 CPU, 6-8 GiB RAM, 100 GiB disk)
- **Worker VMs**: Standard allocation (2 CPU, 6-16 GiB RAM, 100 GiB disk each)
- All VMs use Ubuntu 24.04 LTS cloud images with cloud-init for initial configuration
- Static IPs assigned per VM with VLAN tagging on a shared bridge interface
- SSH access configured via cloud-init with a dedicated service account

### Layer 2: Core Helm Releases

Terraform installs the foundational cluster services before Ansible takes over:

- **MetalLB**: L2 load balancer providing external IPs for services
- **ArgoCD**: GitOps controller deployed via Helm with initial bootstrap configuration

### Layer 3: Ansible Application Deployment

Ansible applies ArgoCD Application manifests and Kubernetes resources for all remaining services. This layer handles ordering dependencies (e.g., Longhorn before Forgejo, Forgejo before Traefik).

## Data Flows

### GitOps Flow

```
Developer ──push──► Forgejo (Git) ──webhook/poll──► ArgoCD
                                                       │
                                        ┌──────────────┤
                                        ▼              ▼
                                  Management      Spoke Clusters
                                   Cluster        (via registered
                                                   kubeconfigs)
```

ArgoCD applications reference Forgejo as a `$values` source. The internal Forgejo service URL is used for Helm value retrieval, ensuring all clusters pull configuration from a single source of truth.

### Observability Flow

```
┌───────────────────┐     ┌───────────────────┐
│   Spoke Clusters  │     │ Management Cluster │
│                   │     │                    │
│  Alloy ───────────┼────►│  Prometheus        │  (metrics via remote write)
│  (collector)      │     │  Loki              │  (logs via push API)
│                   │     │  Tempo             │  (traces via OTLP)
└───────────────────┘     │                    │
                          │       ▼            │
                          │  Grafana           │  (on monitoring cluster)
                          │  (dashboards)      │
                          └────────────────────┘
```

Each spoke cluster runs an Alloy collector that pushes metrics, logs, and traces to the management cluster's observability stack. Grafana runs on the dedicated monitoring cluster and queries Prometheus, Loki, and Tempo for unified dashboards.

### TLS Certificate Flow

```
Cert-Manager ──DNS-01 challenge──► Cloudflare API
     │
     ▼
Let's Encrypt ──certificate──► Kubernetes Secret
                                      │
                                      ▼
                               Traefik IngressRoute
                               (TLS termination)
```

All public-facing services use Let's Encrypt certificates issued via DNS-01 challenges against the Cloudflare API. Traefik terminates TLS and proxies traffic to backend services running in plaintext.

### Networking Flow

```
External Traffic ──► Router (inter-VLAN routing)
                         │
                    ┌────┴────┐
                    ▼         ▼
              Management   Spoke VLANs
              MetalLB IP   MetalLB IPs
                    │         │
                    ▼         ▼
              Traefik     Traefik (per cluster)
              IngressRoutes
```

Each cluster has its own MetalLB instance providing LoadBalancer IPs within its VLAN subnet. A managed router handles inter-VLAN routing. VPN access is provided through Pangolin-Newt for administrative connectivity.

## Key Design Decisions

### Hub-Spoke ArgoCD Model

A single ArgoCD instance on the management cluster controls all deployments. Spoke clusters are registered via kubeconfig and labeled for ApplicationSet targeting. This centralizes GitOps governance while allowing per-cluster customization through Helm values.

**Trade-off**: Single point of failure for deployments, but simplifies secret management and provides a unified deployment view.

### Forgejo as Values Source

Forgejo (self-hosted Git) serves as the `$values` source for all ArgoCD applications. This decouples application manifests from external Git providers and ensures the cluster can self-heal even if external services are unavailable.

**Dependency**: Longhorn must be deployed before Forgejo (for persistent storage), and Forgejo must be deployed before Traefik and other services (as their ArgoCD applications reference Forgejo for values).

### Layered Terraform

Infrastructure provisioning is split into two layers to manage dependencies:

- **Layer 1** creates VMs (must complete before Kubernetes bootstrap)
- **Layer 2** installs MetalLB and ArgoCD (requires a running cluster)

This avoids circular dependencies between infrastructure and cluster services.

### Single-Binary Observability

Loki, Tempo, and Prometheus each run in single-binary/standalone mode rather than distributed microservice mode. This reduces resource consumption for a homelab environment while still providing full LGTM (Loki, Grafana, Tempo, Mimir/Prometheus) stack capabilities.

### Storage Architecture

- **Longhorn**: Default StorageClass with 3-way replication for pod persistent volumes
- **MinIO**: S3-compatible object storage on the storage cluster, used as backend for Loki (log chunks) and Tempo (trace data)

### Authentication

Keycloak provides SSO/OIDC for services like Grafana. Realm configuration is imported via ConfigMap, with client secrets managed through Ansible Vault.

## Invariants

- **Deployment ordering**: VMs → Kubernetes → ArgoCD → Longhorn → Forgejo → remaining services. Violating this order causes failures due to missing dependencies.
- **Forgejo availability**: All ArgoCD applications reference Forgejo for Helm values. If Forgejo is unreachable, ArgoCD cannot sync applications.
- **MetalLB requirement**: All LoadBalancer-type services depend on MetalLB for IP assignment. MetalLB must be healthy before any service can be exposed.
- **Ansible Vault**: All secrets are stored in Ansible Vault. The vault password is required for any deployment operation.
- **VLAN isolation**: Each cluster operates on a dedicated VLAN. Cross-cluster communication relies on the router for inter-VLAN routing.

## Kubernetes Details

| Component    | Version / Chart                                   |
|--------------|---------------------------------------------------|
| Kubernetes   | v1.31                                             |
| Container Runtime | containerd                                   |
| CNI          | Flannel                                           |
| OS           | Ubuntu Noble 24.04 LTS                            |
| ArgoCD       | Helm chart argo-cd v9.4.4                         |
| Traefik      | Helm chart traefik v32.1.1 (image v3.6.7)        |
| Cert-Manager | Helm chart cert-manager v1.14.4                   |
| MetalLB      | Helm chart metallb v0.15.3                        |
| Longhorn     | Helm chart longhorn v1.7.3                        |
| Vault        | Helm chart vault v0.29.1                          |
| Keycloak     | Helm chart keycloakx v2.5.0                       |
| Forgejo      | Helm chart forgejo v16.2.1 (OCI)                  |
| Prometheus   | Helm chart kube-prometheus-stack v69.3.2           |
| Loki         | Helm chart loki v6.25.0                           |
| Tempo        | Helm chart tempo v1.14.0                          |
| Alloy        | Helm chart k8s-monitoring v2.0.6                  |
| Pangolin-Newt| Helm chart newt v1.2.0                            |

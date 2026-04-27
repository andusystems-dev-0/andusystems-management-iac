# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- Portfolio cluster deployment with ArgoCD integration and cluster-status application.
- Cluster status application to Portfolio cluster.
- ArgoCD cluster registration tasks for monitoring and networking clusters with kubeconfig validation and secret labeling for ApplicationSet generation.
- Storage cluster registration and management tasks in Ansible playbook.
- Tasks to push spoke cluster repositories to Forgejo for ArgoCD integration.
- Documented Traefik configuration in development guide (providers, entrypoints, RBAC, additional arguments, dashboard).
- Bumped Alloy resource limits to prevent OOMKilled on management cluster.
- Enabled additional Ansible playbooks for Andusystems clusters in `apps.yml`.
- Added policy rule for GitHub Actions in ArgoCD cleanup tasks.
- Generated and updated project documentation (README, architecture, development guide, changelog).

### Changed
- Updated Newt Helm chart from 1.2.0 to 1.3.0 (Newt 1.11.0) for Pangolin 1.17.0 server compatibility.
- Reverse proxy health endpoints instead of direct exposure.
- Refactored ArgoCD repository configuration to use Forgejo URL; removed duplicate GitHub SSH URL for slimerio.
- Reordered Forgejo playbook import in `apps.yml` for consistent deployment sequencing.
- Temporarily disabled FleetDock cluster deployment in `deploy.yml` pending reconfiguration.
- Refactored GitHub Runner installation to use `helm` command directly instead of Ansible Helm module.
- Improved ARC controller and runner scale set installation with updated command syntax and Helm output registration.
- Updated ARC controller label selector for deployment detection.
- Integrated Forgejo into deployment playbooks and streamlined ArgoCD configurations.
- Updated ArgoCD login and repository registration to use public access URLs.
- Enhanced Forgejo user management and repository creation automation.

### Fixed
- Pinned ArgoCD LoadBalancer IP via MetalLB annotation; removed `--insecure-registry` from runner configuration.

## [2026-04-04]

### Added
- Slimerio playbook for cluster registration and ArgoCD integration.

### Changed
- Updated Forgejo routes and ingress configuration.

### Fixed
- Traefik LoadBalancer IP for ArgoCD connectivity.
- Removed temporary repository exclusions from `apps.yml`.

## [2026-03-23]

### Added
- Keycloak-Grafana realm integration for SSO login.

### Changed
- Updated Keycloak and Grafana configurations for OIDC authentication.
- Exposed Grafana services via LoadBalancer IP.

### Fixed
- Monitoring component deployment issues.

## [2026-03-17]

### Added
- Management LGTM (Loki, Grafana, Tempo, Metrics) stack values.
- MinIO application dependency for storage cluster.

### Fixed
- Issues with the LGTM observability stack deployment.
- Monitoring application fixes on management cluster.

## [2026-03-15] - Storage & Monitoring Expansion

### Added
- MinIO deployment to management configurations.
- Storage cluster monitoring applications.
- Updated andusystems-monitoring manifest for Grafana.

### Changed
- Updated PiHole Helm chart version.

## [2026-03-14] - Forgejo Migration & Multi-Cluster

### Added
- Forgejo deployment replacing GitLab as the Git service.
- Networking cluster integration with management ArgoCD.
- FleetDock cluster configuration changes.
- Automated Forgejo RBAC and user management.

### Changed
- Migrated from GitLab to Forgejo for all Git operations.
- Updated deployment playbooks for multi-cluster support.

### Fixed
- Forgejo IngressRoute port configuration.
- Forgejo deployment issues and values tuning.

## [2026-03-13]

### Changed
- Decommissioned a worker host from the cluster inventory.
- Updated VM RAM allocations.

## [2026-03-11] - GitLab & FleetDock

### Added
- GitLab deployment with initial admin password and HTTPS.
- FleetDock deployment on Pterodactyl cluster.
- ArgoCD password management via Vault.

### Changed
- Allocated more disk space to VMs.
- Updated Helm chart versions for GitLab.
- Improved ArgoCD setup with HTTPS and DNS configuration.

### Fixed
- OOM exception on Sidekiq.
- ArgoCD Ansible deployment issues with login.
- Removed Keycloak deployment dependency from Longhorn.
- Resolved conflicting ArgoCD server IP vault variable.

## [2026-03-10]

### Added
- Pterodactyl cluster deployment.

## [2026-03-09]

### Added
- Vault and Longhorn deployment on management cluster.
- Values files for deployment configuration.

### Changed
- Updated `.gitignore` to exclude Claude configuration files.

## [2026-03-08] - Certificate & Authentication

### Added
- Keycloak, Pangolin-Newt (VPN), and cert-manager deployment.
- Longhorn distributed storage deployment.
- ClusterIssuer for Let's Encrypt production certificates.
- Cert-manager namespace configuration.

### Fixed
- Cert-manager deployment and namespace issues.
- Keycloak manifest, values, and DNS configuration errors.

## [2026-03-07]

### Added
- Grafana deployment to monitoring cluster.

## [2026-03-06] - Ansible Refactoring & Security

### Added
- Cloudflare API token to Vault for DNS-01 challenges.
- Homepage with VPN connectivity via Pangolin.

### Changed
- Refactored Ansible from monolithic role to modular role-based organization.
- Rearranged monitoring application deployments in logical order.
- Reduced Ansible configuration bloat and improved error handling.
- Added ArgoCD environment templating.
- Obscured sensitive information for open-source readiness.

### Fixed
- Various bugfixes across deployment playbooks.

## [2026-03-05] - Traefik & Homepage

### Added
- Traefik application deployment to management cluster.
- Traefik manifest deployment via Ansible.
- IngressRoute for homepage.

### Fixed
- Homepage manifest ordering and configuration issues.

## [2026-03-04]

### Changed
- Monitoring configuration updates.
- Error handling improvements.

### Added
- Homepage manifest for hub ArgoCD cluster management.

## [2026-03-02]

### Changed
- Cleaned up ArgoCD values (removed auto-generated configuration).
- Enabled ArgoCD hub-spoke design for multi-cluster management.

## [2026-03-01]

### Changed
- Updated Terraform configuration to fix bugs in VM creation.
- Adjusted default cluster name.
- Disabled Traefik temporarily during initial setup.
- Removed unused Vault configuration.

## [2026-02-26] - Initial Release

### Added
- Initial project setup for management cluster.
- Terraform Layer 1: Proxmox VM provisioning with cloud-init.
- Terraform Layer 2: MetalLB and ArgoCD Helm releases.
- Ansible playbooks for Kubernetes v1.31 bootstrap.
- ArgoCD deployment and configuration.
- Base infrastructure for multi-VLAN homelab.

Repository for the management cluster in the following stack:

## VLAN 10: Management & Internal Services (10.10.10.0/24)
- ArgoCD (main instance)
- Terraform/Ansible runners
- Vault (secrets management)
- Authentik (SSO for ALL apps)
- Mail server (optional)
- Traefik (internal ingress)
- Cert-Manager
- Tailscale/Pangolin (VPN for admin + friends if allowed)
- ClamAV (scanning service)
- Wazuh agent
- Gitlab?

## VLAN 20: DMZ/Password Manager (10.10.20.0/24)
- Vaultwarden
- Traefik (for Vaultwarden only)
- Cert-Manager
- Tailscale/Pangolin (VPN access for you only)
- ArgoCD (cluster-local)

## VLAN 30: Public Applications / Will create multiple of these for each public app, start with FleetDock, create another when code project goes public (10.10.30.0/24)
- FleetDock
- Traefik (public ingress with WAF)
- Cert-Manager
- Tailscale/Pangolin (admin VPN access only)
- ArgoCD (cluster-local)
- Wazuh agent

## VLAN 40: Storage (10.10.40.0/24)
- Longhorn
- MinIO
- Nexus Repository
- Backup system
- ArgoCD (cluster-local)
- Wazuh agent

## VLAN 50: Monitoring (10.10.50.0/24)
- Uptime Kuma
- CheckMK
- Grafana/Prometheus
- Kiali/Istio
- Loki (logs)
- Tailscale/Pangolin (admin VPN access only)
- ArgoCD (cluster-local)
- Wazuh (central SIEM server)
- Homepage (Dashboard for management)
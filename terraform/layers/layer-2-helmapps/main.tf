# Installs MetalLB Helm Chart for CRDs
resource "helm_release" "metallb" {
  name       = "metallb"
  repository = "https://metallb.github.io/metallb"
  chart      = "metallb"
  version    = "0.15.3"
  namespace  = "metallb"

  create_namespace = true
}

# Installs ArgoCD Helm Chart for CRDs
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"          # Corrected chart name
  version    = "9.4.4"             # Latest version as of writing this
  namespace  = "argocd"

  create_namespace = true
  timeout  = 30    # ← was 60, needs to be 600
  atomic   = false  # ← prevents rollback on timeout, lets pods finish coming up
  wait     = true
  depends_on = [helm_release.metallb]

  values = [ file("${var.apps_dir}/argocd/values.yml") ]
}

# Installs Traefik Helm Chart for CRDs
#resource "helm_release" "traefik" {
#  name       = "traefik"
#  repository = "https://helm.traefik.io/traefik"
#  chart      = "traefik"
#  version    = "39.0.0"
#  namespace  = "traefik"
#  create_namespace = true
#  
#  values = [
#    file("${var.apps_dir}/traefik/values.yml")
#  ]
#}

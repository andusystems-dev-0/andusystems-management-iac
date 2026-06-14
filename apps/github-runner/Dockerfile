# Custom GitHub Actions runner image for the andusystems IaC repos.
#
# Bakes the tools every IaC workflow uses (ansible-core + kubernetes.core +
# community.general collections, terraform, kubectl, helm, argocd CLI) on top
# of the official actions-runner base image. Pin versions via build args so
# rebuilds are deterministic — the only `:latest` is the runner itself.
#
# Build + push:
#   apps/github-runner/build-and-push.sh
# Consumed by:
#   values-runner-hireship-iac.yml
#   values-runner-management-iac.yml
# Pull secret in the arc-runners namespace:
#   nexus-pull (created by apps/github-runner/manifest.yml).

ARG RUNNER_VERSION=latest
FROM ghcr.io/actions/actions-runner:${RUNNER_VERSION}

USER root

ARG ANSIBLE_CORE_VERSION=2.17.5
ARG TERRAFORM_VERSION=1.9.8
ARG KUBECTL_VERSION=1.31.0
ARG HELM_VERSION=3.16.2
ARG ARGOCD_VERSION=2.13.1

ENV DEBIAN_FRONTEND=noninteractive \
    ANSIBLE_COLLECTIONS_PATH=/usr/share/ansible/collections

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
         ca-certificates curl gnupg jq unzip git openssh-client rsync \
         python3 python3-pip python3-venv \
    && rm -rf /var/lib/apt/lists/*

# ansible-core + python deps used by kubernetes.core (kubernetes client) and
# the templated Secrets that hash passwords via passlib.
RUN pip3 install --no-cache-dir --break-system-packages \
      "ansible-core==${ANSIBLE_CORE_VERSION}" \
      kubernetes \
      passlib

# Pre-install the collections every IaC role uses so workflows don't pay the
# galaxy install cost on every run. Installing system-wide so all subsequent
# UIDs see them (the runner pod runs as `runner`, not root).
RUN ansible-galaxy collection install -p "${ANSIBLE_COLLECTIONS_PATH}" \
      kubernetes.core \
      community.general

RUN curl -fsSLo /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    && chmod +x /usr/local/bin/kubectl

RUN curl -fsSL "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" \
      | tar -xz -C /tmp \
    && mv /tmp/linux-amd64/helm /usr/local/bin/helm \
    && rm -rf /tmp/linux-amd64

RUN curl -fsSLo /usr/local/bin/argocd \
      "https://github.com/argoproj/argo-cd/releases/download/v${ARGOCD_VERSION}/argocd-linux-amd64" \
    && chmod +x /usr/local/bin/argocd

RUN curl -fsSLo /tmp/tf.zip \
      "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" \
    && unzip -d /usr/local/bin /tmp/tf.zip \
    && rm /tmp/tf.zip

USER runner

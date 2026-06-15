#!/usr/bin/env bash
# Bootstrap the management cluster's Vault for use by IaC GitHub Actions
# workflows.
#
# This script is idempotent — safe to re-run after secret rotations, after
# Vault restarts (it'll re-unseal), or after adding new IaC repos to the
# mix (just append to the REPOS array below).
#
# What it does:
#   1. Unseal Vault using ~/.vault-keys.json if it's sealed.
#   2. Log in as root (token from same file).
#   3. Enable the JWT auth method at /auth/github-actions (if missing).
#   4. Point it at GitHub's OIDC issuer.
#   5. For each IaC repo:
#        a. Write a Vault policy granting read access to secret/data/iac/<repo>.
#        b. Create a JWT role bound to that repo's `sub` claim.
#        c. Read the local plaintext `vault` file and push every `vault_*`
#           entry into secret/iac/<repo> as a single KV entry (one field
#           per var). Existing values are overwritten.
#
# Why local-vault → Vault: we use the existing plaintext `ansible/inventory/
# */group_vars/all/vault` files as the source of truth for the migration.
# After this runs cleanly and workflows are confirmed working, those local
# files should be deleted (or symlinked to /dev/null) so Vault becomes the
# only place secrets live.
#
# Run from the andusystems-management repo root:
#   ./scripts/vault-bootstrap.sh
#
# Prereqs on workstation:
#   - vault CLI (>=1.18)
#   - kubectl with the management kubeconfig active
#   - ~/.vault-keys.json (or repo-relative .vault-keys.json) with init output
#   - Each repo's plaintext `ansible/inventory/*/group_vars/all/vault` present
#     at the path declared in REPOS below.

set -euo pipefail

# ────────────────────────────────────────────────────────────────────────────
# Config
# ────────────────────────────────────────────────────────────────────────────

VAULT_ADDR="${VAULT_ADDR:-https://vault.andusystems.com}"
export VAULT_ADDR
# We've installed the LE cert chain on the cluster; if it's still snake-oil
# at first run, set VAULT_SKIP_VERIFY=1 in the environment to bypass.

KEYS_FILE="${VAULT_KEYS_FILE:-$(dirname "$0")/../.vault-keys.json}"
GITHUB_ORG="${GITHUB_ORG:-andusystems-dev-0}"

# Repos to provision. Each entry is:
#   <repo_name>:<plaintext_vault_file_path>:<vault_kv_path_segment>
# The local vault file is read and every `vault_*` key becomes a field in
# the KV entry at secret/iac/<segment>.
REPOS=(
  "andusystems-management-iac:$(dirname "$0")/../ansible/inventory/management/group_vars/all/vault:management"
  "andusystems-hireship-iac:$HOME/andusystems/andusystems-hireship/ansible/inventory/sit/group_vars/all/vault:hireship-sit"
  "andusystems-hireship-iac:$HOME/andusystems/andusystems-hireship/ansible/inventory/prod/group_vars/all/vault:hireship-prod"
)

# ────────────────────────────────────────────────────────────────────────────
# Helpers
# ────────────────────────────────────────────────────────────────────────────

log() { printf '[vault-bootstrap] %s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

require() {
  command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"
}

# Parse a plaintext ansible vault file into KEY=VALUE lines for `vault kv put`.
# Strips quotes from values. Skips comments and blank lines. Only emits
# entries whose key starts with `vault_` (so non-secret vars stay local).
parse_local_vault() {
  local path=$1
  [[ -f $path ]] || die "vault file not found: $path"
  python3 - "$path" <<'PY'
import re, sys
path = sys.argv[1]
with open(path) as f:
    for line in f:
        m = re.match(r'^\s*(vault_[a-zA-Z0-9_]+)\s*:\s*(.*)$', line)
        if not m:
            continue
        key, val = m.group(1), m.group(2).strip()
        # Strip surrounding quotes
        if (val.startswith('"') and val.endswith('"')) or \
           (val.startswith("'") and val.endswith("'")):
            val = val[1:-1]
        # Drop trailing inline comments after a #, but only if preceded by space
        # (so values with # in them aren't mangled — basic heuristic).
        val = re.sub(r'\s+#.*$', '', val)
        # Skip empty values and YAML lists/dicts (those need richer handling
        # later; for IaC secrets they're unlikely).
        if not val or val.startswith('[') or val.startswith('{'):
            continue
        # Use null byte separator so values with newlines survive (vault CLI
        # supports key=@file but not multi-line on the command line easily;
        # this script keeps it simple and only handles single-line scalars).
        print(f"{key}={val}")
PY
}

# ────────────────────────────────────────────────────────────────────────────
# Sanity checks
# ────────────────────────────────────────────────────────────────────────────

require vault
require kubectl
require python3
require jq

[[ -f $KEYS_FILE ]] || die "keys file not found: $KEYS_FILE (run vault operator init first)"

# ────────────────────────────────────────────────────────────────────────────
# 1. Unseal if sealed
# ────────────────────────────────────────────────────────────────────────────

SEALED=$(vault status -format=json 2>/dev/null | jq -r '.sealed' || echo "unreachable")
case "$SEALED" in
  unreachable)
    die "cannot reach $VAULT_ADDR — check DNS, pod, and ingress"
    ;;
  true)
    log "vault is sealed — unsealing"
    threshold=$(jq -r '.unseal_threshold // .keys_threshold // 3' "$KEYS_FILE")
    for i in $(seq 0 $((threshold - 1))); do
      key=$(jq -r ".unseal_keys_b64[$i]" "$KEYS_FILE")
      vault operator unseal "$key" >/dev/null
    done
    log "unsealed"
    ;;
  false)
    log "vault is already unsealed"
    ;;
esac

# ────────────────────────────────────────────────────────────────────────────
# 2. Authenticate as root
# ────────────────────────────────────────────────────────────────────────────

VAULT_TOKEN=$(jq -r '.root_token' "$KEYS_FILE")
export VAULT_TOKEN

vault token lookup >/dev/null || die "root token from $KEYS_FILE is rejected — re-init may be needed"

# ────────────────────────────────────────────────────────────────────────────
# 3. Enable KV v2 at secret/ (kubeadm/dev installs sometimes lack it)
# ────────────────────────────────────────────────────────────────────────────

if ! vault secrets list -format=json | jq -e '."secret/"' >/dev/null; then
  log "enabling KV v2 at secret/"
  vault secrets enable -version=2 -path=secret kv
fi

# ────────────────────────────────────────────────────────────────────────────
# 4. Enable GitHub Actions JWT auth method
# ────────────────────────────────────────────────────────────────────────────

JWT_PATH="github-actions"
if ! vault auth list -format=json | jq -e ".[\"$JWT_PATH/\"]" >/dev/null; then
  log "enabling jwt auth at $JWT_PATH/"
  vault auth enable -path="$JWT_PATH" jwt
fi

# Configure OIDC discovery (idempotent — write always applies the same value)
log "configuring jwt auth to trust github.com/actions"
vault write -f "auth/$JWT_PATH/config" \
  oidc_discovery_url="https://token.actions.githubusercontent.com" \
  bound_issuer="https://token.actions.githubusercontent.com" >/dev/null

# ────────────────────────────────────────────────────────────────────────────
# 5. Per-repo: policy + role + secrets
# ────────────────────────────────────────────────────────────────────────────

for entry in "${REPOS[@]}"; do
  IFS=':' read -r repo_name vault_file kv_segment <<<"$entry"

  log "── $repo_name → secret/iac/$kv_segment ──"

  if [[ ! -f $vault_file ]]; then
    log "  skip: local vault file missing at $vault_file"
    continue
  fi

  policy_name="iac-${kv_segment}"
  role_name="${kv_segment}"

  # 5a. Policy: read-only access to this repo's KV path
  vault policy write "$policy_name" - <<EOF >/dev/null
path "secret/data/iac/${kv_segment}" {
  capabilities = ["read"]
}
EOF
  log "  policy: $policy_name"

  # 5b. JWT role bound to this specific repo. Allow any ref (branch/tag)
  #     for now — tighten to `:ref:refs/heads/main` once workflows are stable.
  # Map-typed fields (bound_claims) must be passed as JSON via stdin; the
  # `key=value` CLI form stringifies them and gets rejected.
  vault write "auth/$JWT_PATH/role/$role_name" - >/dev/null <<EOF
{
  "role_type": "jwt",
  "bound_audiences": ["https://github.com/$GITHUB_ORG"],
  "bound_claims_type": "glob",
  "bound_claims": {"sub": "repo:$GITHUB_ORG/$repo_name:*"},
  "user_claim": "sub",
  "policies": ["$policy_name"],
  "ttl": "15m"
}
EOF
  log "  role  : $role_name  (bound to repo:$GITHUB_ORG/$repo_name:*)"

  # 5c. Populate KV
  kv_args=()
  while IFS= read -r line; do
    [[ -z $line ]] && continue
    kv_args+=("$line")
  done < <(parse_local_vault "$vault_file")

  if [[ ${#kv_args[@]} -eq 0 ]]; then
    log "  no vault_* keys parsed from $vault_file — nothing written"
    continue
  fi

  vault kv put "secret/iac/$kv_segment" "${kv_args[@]}" >/dev/null
  log "  kv    : wrote ${#kv_args[@]} keys"
done

log ""
log "done. Next steps:"
log "  1. Configure each IaC workflow with hashicorp/vault-action."
log "  2. After workflows confirmed working, delete local plaintext"
log "     vault files (or symlink to /dev/null) so Vault is the only source."
log "  3. Re-run this script after rotating any secret to push the new"
log "     value into Vault (idempotent)."

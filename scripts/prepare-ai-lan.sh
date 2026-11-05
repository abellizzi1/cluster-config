#!/bin/bash
set -euo pipefail

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
bash "$project_root/scripts/connect-cluster.sh" "${CLUSTER_NAME:-ai-lan}"
export KUBECONFIG="$project_root/.kubeconfig"

# Bootstrap data before registering the app so the gateway cannot initialize
# a new schema while a backup is being restored.
managed_app=$(kubectl get application ai-lan --namespace argocd --ignore-not-found -o name)
if [ -n "$managed_app" ]; then
  echo "ai-lan is already managed by Argo CD. Use configure-ai-secrets.sh for secret updates; restore only during explicit maintenance." >&2
  exit 1
fi

# Read the same Git source as Argo; only the database manifest is needed here.
application_file="$project_root/clusters/local/ai-lan-application.yaml"
config_repo=$(kubectl create --dry-run=client --validate=false -f "$application_file" -o jsonpath='{.spec.source.repoURL}')
config_revision=$(kubectl create --dry-run=client --validate=false -f "$application_file" -o jsonpath='{.spec.source.targetRevision}')
repo_path="${config_repo#https://github.com/}"
repo_path="${repo_path%/}"
repo_path="${repo_path%.git}"
if [[ ! "$repo_path" =~ ^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || [ -z "$config_revision" ]; then
  echo "AI preparation requires a GitHub HTTPS repo URL and a branch, tag, or commit in $application_file." >&2
  exit 1
fi
postgres_manifest=$(mktemp)
trap 'rm -f -- "$postgres_manifest"' EXIT
curl_headers=(--header "Accept: application/vnd.github.raw+json")
if [ -n "${GITHUB_TOKEN:-}" ]; then
  curl_headers+=(--header "Authorization: Bearer $GITHUB_TOKEN")
fi
if ! curl --fail --silent --show-error --location --get \
  --connect-timeout 10 --max-time 60 \
  --data-urlencode "ref=$config_revision" "${curl_headers[@]}" \
  --output "$postgres_manifest" \
  "https://api.github.com/repos/$repo_path/contents/base/postgres.yaml"; then
  echo "Could not download the PostgreSQL manifest. Check the configured Git source; for private repositories, set GITHUB_TOKEN with Contents read access." >&2
  exit 1
fi

bash "$project_root/scripts/configure-ai-secrets.sh"
kubectl apply --namespace ai-lan -f "$postgres_manifest"
kubectl rollout status deployment/postgres --namespace ai-lan --timeout=180s
table_count=$(kubectl exec --namespace ai-lan deployment/postgres -- psql -U ai_gateway -d ai_gateway -tAc "SELECT COUNT(*) FROM pg_tables WHERE schemaname='public' AND tablename NOT LIKE 'pg_%'")
if [ "$table_count" = "0" ]; then
  shopt -s nullglob
  backups=("$project_root"/backups/postgres-*.dump)
  if [ "${#backups[@]}" -gt 0 ]; then
    gateway=$(kubectl get deployment gateway --namespace ai-lan --ignore-not-found -o name)
    if [ -n "$gateway" ]; then
      echo "Refusing restore while an existing gateway deployment could write to the database. Stop it during maintenance first." >&2
      exit 1
    fi
    latest_backup="${backups[${#backups[@]}-1]}"
    echo "Restoring PostgreSQL from $(basename "$latest_backup")."
    kubectl exec --namespace ai-lan -i deployment/postgres -- \
      pg_restore -U ai_gateway -d ai_gateway --no-owner --exit-on-error --single-transaction < "$latest_backup"
  else
    echo "No PostgreSQL backup found; starting with a fresh database."
  fi
else
  echo "Existing PostgreSQL tables found; preserving the database."
fi
echo "AI data is ready. Register bootstrap/ after configuring and pushing the Git repositories."

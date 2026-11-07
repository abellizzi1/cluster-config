#!/bin/bash
set -euo pipefail

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
: "${LANMARK_API_TOKEN:?Set LANMARK_API_TOKEN to a random administrator token (32+ characters)}"
: "${LANMARK_AGENT_TOKEN:?Set LANMARK_AGENT_TOKEN to a different random ingestion token (32+ characters)}"
: "${GRAFANA_ADMIN_PASSWORD:?Set GRAFANA_ADMIN_PASSWORD}"
if [ "${#LANMARK_API_TOKEN}" -lt 32 ] || [ "${#LANMARK_AGENT_TOKEN}" -lt 32 ] || [ "$LANMARK_API_TOKEN" = "$LANMARK_AGENT_TOKEN" ]; then
  echo "Lanmark API and agent tokens must be distinct and contain at least 32 characters." >&2
  exit 1
fi
bash "$project_root/scripts/connect-cluster.sh" "${CLUSTER_NAME:-ai-lan}"
export KUBECONFIG="$project_root/.kubeconfig"
kubectl create namespace lanmark --dry-run=client -o yaml | kubectl apply --server-side --field-manager=lanmark-bootstrap -f -
kubectl create secret generic lanmark-secrets --namespace lanmark \
  --from-literal="api-token=$LANMARK_API_TOKEN" \
  --from-literal="agent-token=$LANMARK_AGENT_TOKEN" \
  --from-literal="grafana-admin-password=$GRAFANA_ADMIN_PASSWORD" \
  --from-literal="notification-webhook-url=${NOTIFICATION_WEBHOOK_URL:-}" \
  --dry-run=client -o yaml | kubectl apply -f -
echo "Lanmark secrets configured. Restart lanmark after changing environment secrets. Grafana uses the admin password only when its database is first initialized; change an existing password in Grafana."

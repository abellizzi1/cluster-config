#!/bin/bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
bash "$script_dir/connect-cluster.sh" "${CLUSTER_NAME:-apps-cluster}"
export KUBECONFIG="$script_dir/../.kubeconfig"

# Accept the previous environment names during migration; secrets no longer
# pass through Terraform or live in either configuration repository.
: "${GATEWAY_API_KEY:=${TF_VAR_gateway_api_key:-}}"
: "${GATEWAY_ADMIN_USERNAME:=${TF_VAR_gateway_admin_username:-admin}}"
: "${POSTGRES_PASSWORD:=${TF_VAR_postgres_password:-}}"
: "${PROVIDER_API_KEY:=${TF_VAR_provider_api_key:-}}"
# API keys are single-line tokens. Remove CRLF copied from Windows env files.
PROVIDER_API_KEY=$(printf '%s' "$PROVIDER_API_KEY" | tr -d '\r\n')
: "${GATEWAY_API_KEY:?Set GATEWAY_API_KEY to the bootstrap administrator password}"
: "${POSTGRES_PASSWORD:?Set POSTGRES_PASSWORD to the existing or new database password}"

kubectl create namespace ai-lan --dry-run=client -o yaml | kubectl apply --server-side --field-manager=ai-lan-bootstrap -f -
kubectl create secret generic gateway-secrets --namespace ai-lan --from-literal="gateway-api-key=$GATEWAY_API_KEY" --from-literal="gateway-admin-username=$GATEWAY_ADMIN_USERNAME" --from-literal="provider-api-key=$PROVIDER_API_KEY" --from-literal="postgres-password=$POSTGRES_PASSWORD" --dry-run=client -o yaml | kubectl apply -f -
echo "Secrets configured for ai-lan."

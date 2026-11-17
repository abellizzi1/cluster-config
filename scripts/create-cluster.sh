#!/bin/bash
set -euo pipefail

cluster_name="$1"
http_port="$2"
argocd_http_port="${ARGOCD_HTTP_PORT:-8082}"
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

if [ "$http_port" = "$argocd_http_port" ]; then
  echo "HTTP_PORT and ARGOCD_HTTP_PORT must use different host ports." >&2
  exit 1
fi

if k3d cluster get "$cluster_name" >/dev/null 2>&1; then
  k3d cluster start "$cluster_name" --wait
  # Add the mapping to an existing cluster without replacing its nodes/data.
  if ! docker port "k3d-$cluster_name-serverlb" 30080/tcp 2>/dev/null | grep -Fxq "127.0.0.1:$argocd_http_port"; then
    k3d cluster edit "$cluster_name" --port-add "127.0.0.1:${argocd_http_port}:30080@loadbalancer"
  fi
else
  echo "Starting cluster: $cluster_name"
  k3d cluster create "$cluster_name" \
    --servers 1 --agents 1 \
    --image "${K3S_IMAGE:-rancher/k3s:v1.34.3-k3s1}" \
    --port "0.0.0.0:${http_port}:80@loadbalancer" \
    --port "127.0.0.1:${argocd_http_port}:30080@loadbalancer" \
    --wait
fi

bash "$script_dir/connect-cluster.sh" "$cluster_name"
echo "Cluster $cluster_name is ready."

#!/bin/bash
set -euo pipefail

cluster_name="$1"
http_port="$2"
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
server_container="k3d-$cluster_name-server-0"

for tool in docker k3d kubectl; do
  command -v "$tool" >/dev/null 2>&1 || { echo "$tool is required" >&2; exit 1; }
done

# Do not mistake a daemon/CLI failure for an absent cluster.
docker info >/dev/null
k3d cluster list >/dev/null

if k3d cluster get "$cluster_name" >/dev/null 2>&1; then
  if ! docker container inspect "$server_container" >/dev/null 2>&1; then
    echo "Cluster $cluster_name is incomplete: $server_container is missing. Inspect the remaining containers and backups before manual recovery; nothing was deleted." >&2
    exit 1
  fi
  # This reuses running clusters and resumes stopped clusters without replacing
  # their containers, Kubernetes version, or data volumes.
  k3d cluster start "$cluster_name" --wait
else
  remaining_containers=$(docker ps -a --filter "name=k3d-$cluster_name-" --format '{{.Names}}')
  if [ -n "$remaining_containers" ]; then
    echo "Containers for $cluster_name still exist, but k3d cannot find a complete cluster. Inspect them before manual recovery; refusing to replace them." >&2
    exit 1
  fi
  echo "Cluster $cluster_name is absent; creating it."
  k3d cluster create "$cluster_name" \
    --servers 1 --agents 1 \
    --image "${K3S_IMAGE:-rancher/k3s:v1.34.3-k3s1}" \
    --port "0.0.0.0:${http_port}:80@loadbalancer" \
    --wait
fi

bash "$project_root/scripts/connect-cluster.sh" "$cluster_name"
echo "Cluster $cluster_name is ready."

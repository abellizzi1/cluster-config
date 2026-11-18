#!/bin/bash
set -euo pipefail

cluster_name="$1"
http_port="$2"
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

if docker container inspect "k3d-$cluster_name-server-0" >/dev/null 2>&1; then
  echo "Starting existing cluster: $cluster_name"
  k3d cluster start "$cluster_name" --wait
else
  echo "Creating cluster: $cluster_name"
  k3d cluster create "$cluster_name" \
    --servers 1 --agents 1 \
    --image "${K3S_IMAGE:-rancher/k3s:v1.34.3-k3s1}" \
    --port "0.0.0.0:${http_port}:80@loadbalancer" \
    --wait
fi

bash "$script_dir/connect-cluster.sh" "$cluster_name"
echo "Cluster $cluster_name is ready."

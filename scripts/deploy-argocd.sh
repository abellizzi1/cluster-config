#!/bin/bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

: "${CLUSTER_NAME:=apps-cluster}"
: "${HTTP_PORT:=8080}"
: "${ARGOCD_VERSION:=v3.5.6}"

# Terraform state can outlive the actual Docker cluster containers.
bash "$script_dir/create-cluster.sh" "$CLUSTER_NAME" "$HTTP_PORT"
export KUBECONFIG="$script_dir/../.kubeconfig"

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply --namespace argocd --server-side --force-conflicts -f "https://raw.githubusercontent.com/argoproj/argo-cd/$ARGOCD_VERSION/manifests/install.yaml"
kubectl wait --for=condition=Established --timeout=120s crd/applications.argoproj.io crd/appprojects.argoproj.io crd/applicationsets.argoproj.io
kubectl rollout status deployment/argocd-redis --namespace argocd --timeout=300s
kubectl rollout status deployment/argocd-repo-server --namespace argocd --timeout=300s
kubectl rollout status deployment/argocd-server --namespace argocd --timeout=300s
kubectl rollout status statefulset/argocd-application-controller --namespace argocd --timeout=300s
echo "Argo CD is ready. Prepare AI secrets/data, then apply bootstrap/ (see README.md)."

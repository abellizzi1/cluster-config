#!/bin/bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

: "${CLUSTER_NAME:=apps-cluster}"
: "${HTTP_PORT:=8080}"
: "${ARGOCD_VERSION:=v3.5.6}"

wait_for_crd() {
  local crd_name="$1"
  local timeout_seconds="${2:-180}"
  local deadline=$((SECONDS + timeout_seconds))

  echo "Waiting for CRD $crd_name to become Established."
  while (( SECONDS < deadline )); do
    # Newly created CRDs can have null conditions, which makes kubectl wait
    # --for=condition fail immediately. Go-template range tolerates null/missing status.
    if [ "$(kubectl get crd "$crd_name" --request-timeout=5s \
      -o go-template='{{with .status}}{{range .conditions}}{{if eq .type "Established"}}{{.status}}{{end}}{{end}}{{end}}' 2>/dev/null)" = "True" ]; then
      echo "CRD $crd_name is Established."
      return 0
    fi
    sleep 2
  done

  echo "Timed out after ${timeout_seconds}s waiting for CRD $crd_name to become Established." >&2
  kubectl get crd "$crd_name" --request-timeout=5s >&2 || true
  return 1
}

bash "$script_dir/create-cluster.sh" "$CLUSTER_NAME" "$HTTP_PORT"
export KUBECONFIG="$script_dir/../.kubeconfig"

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply --namespace argocd --server-side --force-conflicts -f "https://raw.githubusercontent.com/argoproj/argo-cd/$ARGOCD_VERSION/manifests/install.yaml"

wait_for_crd middlewares.traefik.io
kubectl wait --for=create --timeout=180s deployment/traefik --namespace kube-system
kubectl rollout status deployment/traefik --namespace kube-system --timeout=180s

# Serve at /argocd, preserving the path prefix.
kubectl apply --namespace argocd --server-side --field-manager=argocd-local -k "$script_dir/../argocd"

kubectl rollout restart deployment/argocd-server --namespace argocd
wait_for_crd applications.argoproj.io 120
wait_for_crd appprojects.argoproj.io 120
wait_for_crd applicationsets.argoproj.io 120
kubectl rollout status deployment/argocd-redis --namespace argocd --timeout=300s
kubectl rollout status deployment/argocd-repo-server --namespace argocd --timeout=300s
kubectl rollout status deployment/argocd-server --namespace argocd --timeout=300s
kubectl rollout status statefulset/argocd-application-controller --namespace argocd --timeout=300s
echo "Argo CD UI: http://localhost:$HTTP_PORT/argocd/"
echo "Argo CD is ready. Prepare AI secrets/data, then apply bootstrap/ (see README.md)."

#!/bin/bash
set -euo pipefail

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
bash "$project_root/scripts/connect-cluster.sh" "${CLUSTER_NAME:-ai-lan}"
export KUBECONFIG="$project_root/.kubeconfig"
umask 077
mkdir -p "$project_root/backups"
timestamp=$(date -u +%Y%m%dT%H%M%S%NZ)
backup_file="$project_root/backups/lanmark-$timestamp.db"
temp_file="$backup_file.tmp"
trap 'rm -f -- "$temp_file"' EXIT
# Works while Lanmark is live and after teardown scales it down. A temporary
# reader pod uses the same PVC and SQLite's backup API, including WAL contents.
pod_name="lanmark-backup-$(date +%s)-$RANDOM"
cleanup() {
  kubectl delete pod "$pod_name" --namespace lanmark --ignore-not-found --wait=true --timeout=60s >/dev/null
  rm -f -- "$temp_file"
}
trap cleanup EXIT
kubectl run "$pod_name" --namespace lanmark --restart=Never --image=python:3.12-slim \
  --overrides='{"spec":{"automountServiceAccountToken":false,"securityContext":{"runAsUser":10001,"runAsGroup":10001,"fsGroup":10001},"containers":[{"name":"backup","image":"python:3.12-slim","command":["sleep","600"],"volumeMounts":[{"name":"data","mountPath":"/data"}]}],"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"lanmark-data"}}]}}'
kubectl wait --namespace lanmark --for=condition=Ready "pod/$pod_name" --timeout=180s
kubectl exec --namespace lanmark "$pod_name" -- python -c \
  'import sqlite3; s=sqlite3.connect("file:/data/lanmark.db?mode=ro",uri=True); d=sqlite3.connect("/tmp/backup.db"); s.backup(d); d.close(); s.close()'
kubectl exec --namespace lanmark "$pod_name" -- cat /tmp/backup.db > "$temp_file"
if [ ! -s "$temp_file" ]; then
  echo "Lanmark backup is empty." >&2
  exit 1
fi
mv -- "$temp_file" "$backup_file"
echo "Lanmark backup completed: $backup_file"

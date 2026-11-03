# Shared cluster application registrations

This directory is ready to become the root of its own Git repository. Terraform in the infrastructure repository creates k3d and installs the pinned Argo CD release. This repo registers applications; it does not build images or install Argo itself.

| Path | Purpose |
| --- | --- |
| `bootstrap/` | Apply once after Argo installation and initial AI secrets/data preparation; registers the trusted bootstrap project and `local-cluster` root Application. |
| `clusters/local/` | Root Application source: per-application projects and child Applications for this cluster. |

Before registration, replace `https://github.com/REPLACE_ME/cluster-config.git` in both bootstrap files and `https://github.com/REPLACE_ME/ai-lan-config.git` in both AI registration files with reachable repository URLs. `main` is the default branch. Publish the contents of each configuration folder at its own repository root. If keeping a monorepo, use its URL for both sources, prefix the root source path with `cluster-config/`, and prefix the child source path with `ai-lan-config/`. Public Git sources require no credentials. Configure private repository access in Argo CD before registering the root; never commit access tokens or SSH keys.

From this repository root, with kubeconfig targeting the intended cluster:

```bash
kubectl kustomize bootstrap
kubectl kustomize clusters/local
# Run only AFTER runtime secrets and any database restore are complete:
kubectl apply -k bootstrap
kubectl -n argocd get applications
```

The infrastructure repo's `scripts/prepare-ai-lan.sh` sets up the AI Secret and restores an empty database before registration. The child Application points to `overlays/lan`. To use local Ollama, change its `spec.source.path` to `overlays/ollama` **before** the first sync and use `ollama` for the runtime provider key. Later, commit application registration changes here and let the root Application sync them. Bootstrap files remain operator-managed; reapply them after changing their URL, branch, or project policy.

The root automatically syncs and repairs drift but does not prune registrations. The child automatically syncs, prunes removed workloads, and repairs drift. Namespace and data PVCs opt out of prune/deletion. Neither Application has a cascading deletion finalizer: deleting a registration leaves its workloads running. To decommission, remove its definition from this repo, explicitly delete its registration, then remove workloads after backing up data. A removed child file alone does not stop deployment because root pruning is disabled.

Only trusted administrators should write to this repository: permission to create AppProjects/Applications in `argocd` grants deployment control. The AI project restricts namespaced workloads to `ai-lan` and a specific Git source. Namespace creation is its only allowed cluster-scoped resource type. The Argo installation itself has cluster administration permissions.

## Add the future monitoring project

1. Create its application configuration repository, namespace plan, runtime secrets, and required data/backup preparation.
2. Copy the AI AppProject/Application pattern to `clusters/local/monitoring-project.yaml` and `monitoring-application.yaml`. Set unique names, the monitoring Git URL/path, destination namespace, and only the resource permissions that application needs. Cluster-scoped monitoring resources such as ClusterRoles require explicit project permissions.
3. Add both files to `clusters/local/kustomization.yaml` and push this repo. The root registers the new application alongside AI.
4. Give its ingress a hostname distinct from the AI catch-all route and configure LAN DNS/hosts entries. Both services then share host port 8080.

Sync waves order projects before Application registration within the root. The applications subsequently reconcile independently; these waves do not enforce workload dependencies across child Applications. The infrastructure teardown removes the whole cluster, so add backup procedures for monitoring data before relying on cluster teardown.

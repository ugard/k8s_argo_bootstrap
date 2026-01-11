# Infrastructure Upgrade Strategy

## Current Status (Jan 2026)

We have identified the following infrastructure components and their upgrade status.

| Component | Current Version (Chart) | Latest Version (Chart) | Status | Action |
| :--- | :--- | :--- | :--- | :--- |
| **Traefik** | `37.1.2` | `38.0.2` | Update Available | **Upgrade** |
| **Velero** | `10.0.10` | `11.3.2` | Update Available | **Upgrade** |
| **Prometheus Stack** | `75.15.1` | `80.13.3` | Update Available | **Upgrade** |
| **OpenEBS** | `4.3.2` | `3.10.0` (Main) | Ambiguous | **Hold** (Version mismatch with repo) |
| **Rook-Ceph** | `v1.17.6` | `v1.18.x` (Est.) | Stable | **Hold** (Verify v1.18 path first) |
| **Tailscale** | `1.88.3` | `1.88.3+` | Likely Current | **Hold** |
| **Cert-Manager** | *Unmanaged* | `v1.16+` | **Critical** | **Import to GitOps** |

## Upgrade Plan

### 1. Cert-Manager (Pre-requisite)
**Issue**: Cert-Manager is running (`cert-manager2` namespace) but is not defined in `templates/` or `kubectl get applications`.
**Risk**: It is unmanaged. Upgrading other components (Ingress) might rely on it.
**Strategy**:
1.  Identify the installed version (`kubectl get deployment -n cert-manager2 -o yaml`).
2.  Create `templates/helm-cert-manager.yaml` matching the current version.
3.  Sync with ArgoCD with `--apply-only` (or let it take over) to bring it under management.
4.  Once managed, plan an upgrade.

### 2. Traefik
**Risk**: Low/Medium. Rolling update usually works.
**Steps**:
1.  Edit `templates/kustomize-traefik.yaml`.
2.  Update `targetRevision` to `38.0.2`.
3.  Commit and Sync.

### 3. Velero
**Risk**: Medium. Backup capability.
**Steps**:
1.  Edit `templates/helm-velero.yaml`.
2.  Update `targetRevision` to `11.3.2`.
3.  **Note**: Check release notes for CRD updates. ArgoCD should handle CRDs, but verify `ServerSideApply` is enabled if needed.

### 4. Prometheus Operator
**Risk**: Medium. Monitoring interruption.
**Steps**:
1.  Edit `templates/helm-prometheus-operator.yaml`.
2.  Update `targetRevision` to `80.13.3`.
3.  **Warning**: Prometheus Operator CRDs (ServiceMonitor, PrometheusRule) often change. If Sync fails on CRDs, you may need to apply them manually or use `Replace=true` sync option in ArgoCD.

## Execution Order
1.  **Traefik**: First, to ensure Ingress is up-to-date.
2.  **Velero**: Second, to ensure backups are working on the new version.
3.  **Prometheus**: Last, as it is observability.

## Rollback Plan
If an upgrade fails:
1.  Revert the `targetRevision` change in git.
2.  Sync ArgoCD to roll back the release.
3.  For CRD issues, restore old CRDs manually if needed (unlikely for these charts).

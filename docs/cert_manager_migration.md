# Cert-Manager Migration Strategy

## Current State
*   **Namespace**: `cert-manager2`
*   **Version**: `v1.16.1`
*   **Installation Method**: Helm (Release name: `cert-manager`)
*   **Custom Webhook**: `cert-manager-dynu-webhook` (Dynu DNS provider)
*   **Configuration**:
    *   ClusterIssuer: `letsencrypt` (DNS01 challenge via Dynu)
    *   Secret: `dynu-secret` (API Key)

## Migration Goals
1.  Bring `cert-manager` and the webhook under ArgoCD management.
2.  Preserve existing certificates and configuration (no downtime).
3.  Migrate the sensitive `dynu-secret` to a git-safe `SealedSecret`.

## Step-by-Step Plan

### 1. Preparation (Directory Structure)
We will create a new application directory `apps/cert-manager` to house:
*   `values.yaml`: Overrides for the main cert-manager chart.
*   `webhook-values.yaml`: Configuration for the Dynu webhook.
*   `cluster-issuers.yaml`: Definition of the `letsencrypt` ClusterIssuer.
*   `sealed-secret.yaml`: The encrypted API key.

### 2. Secret Migration
The existing `dynu-secret` contains the API key. We must extract it, encrypt it using the `kubeseal` controller, and commit the result.
**Action**: Run `kubeseal` to generate `apps/cert-manager/sealed-secret.yaml`.

### 3. Application Definitions
We will create two ArgoCD Applications in `templates/`:
1.  `helm-cert-manager.yaml`:
    *   Source: `jetstack/cert-manager` (v1.16.1)
    *   Destination: `cert-manager2`
    *   **Crucial**: Use release name `cert-manager` to match the existing installation.
2.  `helm-cert-manager-webhook.yaml`:
    *   Source: `https://github.com/dopingus/cert-manager-webhook-dynu` (Chart path)
    *   Destination: `cert-manager2`

### 4. Adoption Process
Since the resources already exist, we rely on ArgoCD's ability to adopt them.
1.  **Sync Options**: We will use `ServerSideApply=true` to smooth over any diffs.
2.  **Resource Ownership**: ArgoCD uses the `app.kubernetes.io/instance` label. The existing Helm install might use its own labels.
    *   *Risk*: If ArgoCD tries to delete and recreate resources, it could cause a blip.
    *   *Mitigation*: We will use `kubectl label --overwrite` to pre-assign the ArgoCD instance label if needed, or simply let ArgoCD adopt by matching the Helm release name. **Matching the Helm release name is the key.**

### 5. Execution Order
1.  Commit the new manifests to git.
2.  **Secret First**: Apply the SealedSecret manually or let ArgoCD sync it. Ensure `dynu-secret` is managed.
3.  **Cert-Manager App**: Sync `helm-cert-manager`. Check for "Out of Sync" diffs. If they are just label changes, proceed.
4.  **Webhook App**: Sync `helm-cert-manager-webhook`.
5.  **ClusterIssuer**: Ensure the `cluster-issuers.yaml` is included in one of the apps (e.g., via a raw manifest source or Kustomize).

## Rollback
If adoption fails:
*   Delete the ArgoCD `Application` resources (with `cascade=false` to leave the pods running).
*   The cluster returns to the unmanaged state.

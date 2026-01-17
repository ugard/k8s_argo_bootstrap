# Agent Guidelines for k8s_argo_bootstrap

This repository is a GitOps repository for managing Kubernetes applications using ArgoCD and Helm. It functions as an "App of Apps," where the root Helm chart manages the deployment of various applications located in the `apps/` directory.

## 1. Build, Lint, and Test Commands

Since this is primarily a configuration repository, "building" and "testing" generally refer to validating configurations and manifests.

### Global
- **Lint Root Chart:**
  ```bash
  helm lint .
  ```
- **Validate Kustomize Applications:**
  To verify that an application's manifests build correctly:
  ```bash
  kubectl kustomize apps/<app-name>
  ```
  *Example:* `kubectl kustomize apps/gitea`

### Custom Applications (e.g., `apps/alert-webhook`)
- **Build Container Image:**
  ```bash
  docker build -t <image-name> apps/<app-name>
  ```
- **Test Scripts:**
  Run scripts locally to verify syntax.
  ```bash
  bash -n apps/alert-webhook/webhook.sh
  ```

## 2. Code Style & Conventions

### Directory Structure
- **Root:** Helm chart definition (`Chart.yaml`, `values.yaml`, `templates/`).
- **`apps/<name>/`:** Individual application configurations.
  - typically uses `kustomization.yaml` to manage resources.
  - may contain `namespace.yaml`, `deployment.yaml`, `service.yaml`, `sealed_secret.yaml`.
- **`templates/`:** ArgoCD Application definitions. Each file here (e.g., `kustomize-gitea.yaml`) instructs ArgoCD to deploy a folder from `apps/`.
- **`scripts/`:** Helper scripts for maintenance (e.g., secret management).

### YAML & Kubernetes Manifests
- **Indentation:** 2 spaces.
- **Naming:** Kebab-case for filenames and resource names (e.g., `gitea-deployment.yaml`, `gitea-service`).
- **Secrets:**
  - **CRITICAL:** NEVER commit Kubernetes `Secret` resources.
  - **ALWAYS** use `SealedSecret` resources.
  - **Management:** Use the provided scripts to manage secrets. Do not manually edit encrypted data strings.
  - See `SEALED_SECRET_MANAGEMENT.md` for workflows.

### Bash Scripting
- **Shebang:** `#!/bin/bash`
- **Indentation:** 4 spaces (as seen in `apps/alert-webhook/webhook.sh`).
- **Conditionals:** Prefer `[[ ... ]]` over `[ ... ]`.
- **Variables:** Use `local` variables inside functions. Quote variables `"$VAR"`.
- **Dependencies:** Keep runtime dependencies minimal for container scripts (e.g., existing scripts use `grep`/`cut` for simple JSON parsing to avoid heavy image dependencies, though `jq` is preferred if available in the environment).

## 3. Workflow Rules for Agents

### Adding a New Application
1.  **Create Directory:** `mkdir apps/<new-app-name>`
2.  **Add Manifests:** Create standard K8s manifests (Deployment, Service, PVC, etc.).
3.  **Kustomization:** Create a `kustomization.yaml` listing the resources.
4.  **Registration:**
    - Create a new file in `templates/` (e.g., `templates/kustomize-<new-app>.yaml`).
    - Define an ArgoCD `Application` resource.
    - Copy the structure from an existing template (e.g., `templates/kustomize-gitea.yaml`), updating `metadata.name`, `spec.destination.namespace`, and `spec.source.path`.

### Managing Secrets
- **Modification:** If you need to modify a secret, **STOP**. You generally cannot do this autonomously because it requires decryption (access to the cluster) or encryption (public key).
- **Instruction:** Instruct the user to run `./edit-sealed-secret.sh <namespace> <secret> [key]` or `./view-secret-key.sh`.
- **Creation:** If creating a NEW secret, guide the user to generate a `SealedSecret` using `kubeseal` or the helper scripts.

### GitOps Flow
- **State:** The `main` branch represents the desired state of the cluster.
- **Sync:** ArgoCD automatically syncs changes from git to the cluster. No manual `kubectl apply` is needed for deployment, only for testing/validation.

## 4. Cursor/Copilot Rules
*No specific .cursor/rules or .github/copilot-instructions.md were found.*

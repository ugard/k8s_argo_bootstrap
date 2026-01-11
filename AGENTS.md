# Agent Guidelines for k8s_argo_bootstrap

This repository is an ArgoCD "App of Apps" bootstrap configuration. It manages the deployment of Kubernetes applications using a combination of Helm charts and Kustomize overlays.

## 1. Build, Lint, and Test Commands

Since this is a configuration repository, "building" and "testing" primarily involve rendering templates and validating YAML syntax.

### Run a Single Test (Validate an App)
To validate the Kustomize configuration for a specific application (e.g., `gitea`):
```bash
# Syntax: kubectl kustomize apps/<app-name>
kubectl kustomize apps/gitea
```
*   **Success**: Outputs the full rendered YAML manifest.
*   **Failure**: Outputs a kustomize build error.

### Render the Bootstrap Chart
To verify the main "App of Apps" Helm chart (the contents of `templates/`):
```bash
# Run from the repository root
helm template .
```

### Linting
To check for YAML syntax errors across the project:
```bash
# Requires yamllint
yamllint .
```

To lint the bootstrap Helm chart:
```bash
helm lint .
```

## 2. Code Style & Conventions

### Directory Structure
*   `apps/<app-name>/`: Contains the actual Kubernetes manifests or Kustomize bases/overlays for an application.
*   `templates/`: Contains ArgoCD `Application` Custom Resources. These tell ArgoCD *what* to deploy (pointing to `apps/` or external Helm charts).
*   `Chart.yaml` & `values.yaml`: Define the bootstrap Helm chart meta-data and global defaults.

### Naming Conventions
*   **ArgoCD Applications (in `templates/`)**:
    *   Prefix with the method used: `kustomize-<name>.yaml` or `helm-<name>.yaml`.
    *   Example: `templates/kustomize-gitea.yaml`, `templates/helm-vikunja.yaml`.
*   **App Directories**: Use lowercase, kebab-case (e.g., `apps/gitea`, `apps/victoria-metrics`).
*   **Manifest Files**: Descriptive names (e.g., `ingress.yaml`, `pvc.yaml`, `sealed_secret.yaml`).

### ArgoCD Application Patterns
When creating a new Application in `templates/`:
1.  **Dynamic Values**: Always use the global values for the destination server and source repo URL to ensure portability.
    ```yaml
    spec:
      destination:
        server: {{ .Values.spec.destination.server }}
      source:
        repoURL: {{ .Values.spec.source.repoURL }}
    ```
2.  **Namespace**: Explicitly define the `destination.namespace`.
3.  **Project**: Default to `default` unless a specific project is required.

### Kustomize Apps (`apps/`)
*   **Self-Contained**: Each folder in `apps/` should be a valid Kustomize base (contain a `kustomization.yaml`).
*   **Secrets**: Do NOT commit base64 encoded secrets. Use **SealedSecrets**.
    *   File naming: `sealed_secret.yaml` or `secret-*.yaml` containing `SealedSecret` resources.

### Formatting
*   **YAML**: Indent with **2 spaces**.
*   **Line Endings**: Unix style (`\n`).
*   **File Extensions**: Use `.yaml` (prefer over `.yml`).

### Error Handling & Safety
*   **Validation**: Always run `kubectl kustomize apps/<new-app>` before committing to ensure the overlay builds.
*   **Destructive Changes**: Be cautious when modifying `PersistentVolumeClaim` manifests to avoid data loss.

## 3. Tooling Assumptions
*   **Helm**: v3+
*   **Kustomize**: Built-in to `kubectl` or standalone.
*   **ArgoCD**: The target controller.

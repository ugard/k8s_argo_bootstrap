# Application Deployment Guide

This repository uses the **ArgoCD "App of Apps"** pattern to manage deployments. The core logic resides in two main directories: `templates/` and `apps/`.

## Directory Structure

*   **`templates/`**: Contains ArgoCD `Application` Custom Resources (CRs).
    *   These files define *what* application to deploy, *where* to deploy it (cluster/namespace), and *how* (Helm chart or Kustomize path).
    *   They act as the entry points for ArgoCD.
*   **`apps/`**: Contains the actual deployment manifests or configuration overlays for applications.
    *   Used when deploying raw manifests or when providing Kustomize overlays.
    *   Also used to store `values.yaml` files for Helm deployments (using the multi-source pattern).

## Deployment Methods

We observe three primary deployment patterns in this cluster:

### 1. Pure Helm (Inline Values)
The ArgoCD Application points directly to a Helm Chart repository. Configuration values are defined inline within the `templates/*.yaml` file using `valuesObject`.

*   **Example**: `templates/helm-velero.yaml`
*   **Best for**: Applications with simple configurations or when you want all config visible in the Application object.

### 2. Pure Kustomize (Local Manifests)
The ArgoCD Application points to a directory inside this repository (e.g., `apps/<app-name>`). That directory contains a `kustomization.yaml` and standard Kubernetes manifests (Deployments, Services, PVCs).

*   **Example**: `templates/kustomize-gitea.yaml` -> `apps/gitea/`
*   **Best for**: Applications without Helm charts, or when you need full control over raw manifests.

### 3. Helm with Git Values (Hybrid)
This pattern uses ArgoCD's **Multiple Sources** feature. It combines a Helm Chart (from an external repo) with a `values.yaml` file stored locally in the `apps/` directory.

*   **Example**: `templates/kustomize-nodered.yaml`
    *   Source 1: Helm Chart `schwarzit/node-red`
    *   Source 2: Git repo path `apps/node-red` (providing `values.yaml`)
*   **Best for**: Complex Helm charts where `values.yaml` is too large to inline or needs to be versioned separately.
*   **Note**: Some files named `kustomize-<app>.yaml` actually use this Helm pattern.

## Deployed Applications

### Infrastructure & Storage
| Application | Method | Description |
| :--- | :--- | :--- |
| **OpenEBS** | Helm + Kustomize | Core storage engine (`helm-openebs`) plus StorageClass definitions (`kustomize-openebs`). |
| **Rook-Ceph** | Helm | Ceph storage provider. |
| **Velero** | Helm + Kustomize | Backup solution (`helm-velero`) plus schedules and healthchecks (`kustomize-velero-healthchecks`). |
| **Traefik** | Kustomize | Ingress controller. |
| **Tailscale** | Kustomize | VPN connectivity. |
| **Prometheus** | Helm | Monitoring stack (Prometheus Operator). |

### Services & Tools
| Application | Method | Description |
| :--- | :--- | :--- |
| **Gitea** | Kustomize | Git hosting service. |
| **Vikunja** | Helm (Hybrid) | To-do list application. |
| **Jellyfin** | Kustomize | Media server. |
| **Immich** | Kustomize | Photo management (`immich` & `immich-kiosk`). |
| **Paperless** | Kustomize | Document management system. |
| **Home Assistant** | Kustomize | Home automation (`hass`). |
| **Node-RED** | Helm (Hybrid) | Flow-based programming tool. |
| **Vaultwarden** | Kustomize | Password manager (Bitwarden compatible). |
| **MinIO** | Kustomize | S3-compatible object storage. |
| **Postgres** | Kustomize | Database service. |

*(Note: This list is not exhaustive. Check `templates/` for the complete list of active applications.)*

## Adding a New Application

1.  **Create Manifests/Config**: Create a directory `apps/<new-app>` and add your Kubernetes manifests (`kustomization.yaml`) or a `values.yaml` file.
2.  **Define ArgoCD App**: Create a file in `templates/` named either `kustomize-<new-app>.yaml` or `helm-<new-app>.yaml`.
3.  **Template**: Use existing files in `templates/` as a reference. Ensure you use the global variables for server and repo URL:
    ```yaml
    server: {{ .Values.spec.destination.server }}
    repoURL: {{ .Values.spec.source.repoURL }}
    ```

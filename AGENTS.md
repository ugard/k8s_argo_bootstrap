# Agent Guidelines for k8s_argo_bootstrap

This repository is a GitOps repository for managing Kubernetes applications using ArgoCD and Helm.

## 0. Subagent Conventions (pi)

### 0.1 Model choice

- **Subagent explorers** of `apps/<name>/` run on `opencode-go/deepseek-v4-flash`:
  - Rationale: 1M context + 384K output, text-only (k8s manifests aren't images), opencode-go subscription (no API keys).
  - Reserved for heavier work (plan / refactor / migrations): `opencode-go/deepseek-v4-pro`.
  - Image-capable models (`claude-sonnet-4.6`, `gemini-3.5-flash`, `gpt-5.4` via `github-copilot`) only when screenshots/diagrams must be decoded.

- **Invocation pattern** (one app per call):
  ```bash
  pi -p --no-session --no-approve --provider opencode-go --model opencode-go/deepseek-v4-flash \
      --tools read,bash \
      "Przeanalizuj apps/<app-name>/ w repo /home/pi/k8s_argo_bootstrap i zwróć zwięzłe podsumowanie:
       komponenty, obrazy, ingress/hosts, storage, secret/sealed-secret, zależności. Odpowiedz po polsku."
  ```
  - Add `--no-session` for ephemeral runs unless you want a reusable session.
  - Give the subagent read-only tools unless editing is explicitly required.
  - Aggregate subagent outputs into `doc/DEPLOYMENTS_INDEX.md` (see that file for the current full inventory).
- Routine tasks (plan, edit, lint, validation) stay on the main agent/model.
- Do **not** install or call external `opencode` CLI; the model is reached through pi via `--provider opencode-go`.

### 0.2 Cluster access (read-only)

The agent can inspect the live Talos + k8s cluster. Configs installed:

| File | Context | Purpose |
|---|---|---|
| `~/.kube/config` | `ai-agent` (token) | kubectl RO — get/list/watch on `pods`, `pods/log`, `pods/status`, `services`, `endpoints`, `nodes`, `namespaces`, `pvc`s, `pv`s, `configmaps`, `events`, `serviceaccounts`, most CRDs (incl. `applications.argoproj.io`) |
| `~/.talos/config` | `reader@t620` | Talos Linux reader (endpoint `192.168.101.198`) |

**Binaries:** `kubectl` v1.36 (`/usr/bin/kubectl`), `talosctl` (`/usr/bin/talosctl`). Pass Talos config explicitly:
`talosctl --talosconfig ~/.talos/config -n <node-IP> <cmd>`.

**Cluster topology (live 2026-06-21):** 5× control-plane Talos nodes — talos-6wr-lvz `.197`, talos-i8d-hmt `.192`, talos-jly-e8b `.198`, talos-k1y-dkc `.193`, talos-95t-m8m `.199`; Kubernetes v1.34.1.

**Routine checks:**
- Argo apps: `kubectl --context ai-agent -n argocd get applications.argoproj.io`
- Pods of an app: `kubectl --context ai-agent -n <ns> get pods -o wide`
- Logs: `kubectl --context ai-agent -n <ns> logs <pod> [-c <container>] [--tail=200]`
- Events: `kubectl --context ai-agent -n <ns> get events --sort-by=.lastTimestamp | tail -30`
- Argo app detail: `kubectl --context ai-agent -n argocd get applications.argoproj.io <name> -o yaml`
- Talos services: `talosctl --talosconfig ~/.talos/config -n 192.168.101.197 service`
- Talos dmesg: `talosctl --talosconfig ~/.talos/config -n 192.168.101.197 dmesg`

⚠️ Always use `--context ai-agent` with kubectl. Do **not** attempt write/apply operations: RBAC is RO and ArgoCD reconciles state from git.

### 0.3 Sync semantics — ArgoCD is **manually** synced

- ArgoCD does **not** auto-sync. Committing/pushing to `main` does **NOT** change cluster state.
- After a meaningful change in git, the user must trigger a sync explicitly:
  ```bash
  argocd app sync <app-name>            # from a host with argocd CLI + login
  # or click "Sync" in the ArgoCD web UI
  ```
- The RO kubeconfig here (`ai-agent`) can **only read** — it cannot run `argocd app sync` or `kubectl apply`. So after pushing changes, **instruct the user to sync**, do not claim the change is live.
- Valid pre-sync verification steps the agent **can** do locally: `helm lint .`, `kubectl kustomize apps/<name>`, `bash -n` on scripts.
- To observe sync progress after the user triggers it: `kubectl --context ai-agent -n argocd get applications.argoproj.io <name> -o yaml | grep -A3 syncStatus`.

### 0.3 Discovered drift (live vs repo, 2026-06-21)

ArgoCD Applications flagged for future investigation:

| App | Sync | Health | Note |
|---|---|---|---|
| appflowy | OutOfSync | Missing | not deployed |
| kustomize-bytestash | OutOfSync | Missing | not deployed |
| kustomize-lychee | OutOfSync | Missing | not deployed |
| kustomize-openarchiver | OutOfSync | Missing | not deployed (live per-app manifest drift) |
| node-red | OutOfSync | Missing | not deployed |
| trivy | OutOfSync | Missing | not deployed |
| flashweb | OutOfSync | Healthy | config drift |
| kustomize-paperless | Synced | Progressing | still rolling out |
| rook-ceph | Synced | Degraded | Ceph health issue — check `ceph status` via rook toolbox |
| alert-webhook, firefly-iii, gethomepage, kustomize-grafana, kustomize-hass | OutOfSync | Healthy | minor drift (extra/missing resources) |
 It functions as an "App of Apps," where the root Helm chart manages the deployment of various applications located in the `apps/` directory.

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
- **Sync:** ArgoCD is **manually** synced — pushing to `main` does NOT change cluster state. After the agent commits/pushes, it must instruct the user to sync manually via `argocd app sync <app-name>` or the ArgoCD web UI button.
- **No auto-apply:** Do not run `kubectl apply` against the cluster (RBAC is RO anyway; see section 0.2). `kubectl apply` is only acceptable for local kustomize build testing without cluster effects.

## 4. Cursor/Copilot Rules
*No specific .cursor/rules or .github/copilot-instructions.md were found.*

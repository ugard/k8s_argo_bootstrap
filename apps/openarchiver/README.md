# OpenArchiver Setup Guide

## Quick Start

### Option 1: Full Automated Setup (Recommended)

1. **Generate all secrets including PostgreSQL credentials:**
   ```bash
   ./scripts/generate-openarchiver-secrets.sh
   ```
   This will generate and seal ALL secrets including:
   - PostgreSQL user/password/database
   - JWT secrets
   - Encryption keys
   - Admin credentials

2. **Commit and push to deploy:**
   ```bash
   git add apps/openarchiver templates/kustomize-openarchiver.yaml scripts/generate-openarchiver-secrets.sh
   git commit -m "Add OpenArchiver application"
   git push
   ```

3. **Wait for ArgoCD sync** - The migration job will automatically create the PostgreSQL database and user.

---

### Option 2: Manual PostgreSQL Setup

If you prefer to manually set up PostgreSQL before deployment:

1. **Create PostgreSQL user and database:**
   ```bash
   ./scripts/create-openarchiver-postgres-user.sh
   ```
   This script will:
   - Connect to shared postgres pod
   - Create database `open_archive`
   - Create user with random or custom credentials
   - Grant all privileges

2. **Generate remaining secrets:**
   Edit `scripts/generate-openarchiver-secrets.sh` and comment out the PostgreSQL credential generation, or manually set the generated values when the script prompts.

3. **Proceed with deployment** as in Option 1.

---

## Post-Deployment Steps

### 1. Verify Database Migration

If using Option 1, check that the migration job completed:
```bash
kubectl logs -n openarchiver job/openarchiver-migrate
```

### 2. Verify Pods are Running

```bash
kubectl get pods -n openarchiver
```

Expected pods:
- `openarchiver-XXXXXX` - Main application
- `valkey-XXXXXX` - Redis-compatible queue
- `meilisearch-XXXXXX` - Search engine
- `tika-XXXXXX` - Document parser
- `openarchiver-migrate-XXXXXX` - Migration job (completed)

### 3. Access the Application

- URL: `https://openarchiver.ugard.win`
- Login with credentials displayed by `generate-openarchiver-secrets.sh`
- Default username: `admin@local.com`
- **Change the admin password immediately after first login**

### 4. Configure Email Sources

In the OpenArchiver UI, configure your email ingestion sources:
- Google Workspace (Gmail)
- Microsoft 365
- Generic IMAP server
- PST files
- Other supported formats

---

## Troubleshooting

### Migration Job Fails

Check logs:
```bash
kubectl logs -n openarchiver job/openarchiver-migrate
```

Common issues:
- Shared postgres not accessible from openarchiver namespace
- Network policies blocking connections
- PostgreSQL pod not ready

### Pods Not Starting

Check events:
```bash
kubectl describe pod -n openarchiver <pod-name>
```

Check logs:
```bash
kubectl logs -n openarchiver <pod-name>
```

### Secrets Not Applied

Verify SealedSecret was created:
```bash
kubectl get sealedsecret -n openarchiver
```

Check for unsealed secret:
```bash
kubectl get secret openarchiver -n openarchiver
```

---

## Storage Management

### PVC Sizes

- `openarchiver-data`: 50Gi - Email storage (expandable)
- `openarchiver-meilidata`: 5Gi - Search indexes
- `openarchiver-valkey-data`: 1Gi - Redis queue

### Backups

PVCs labeled `backup-this-pvc: true` are backed up by Velero:
- `openarchiver-data`
- `openarchiver-meilidata`

### Expanding Storage

To expand email storage:
```bash
kubectl patch pvc openarchiver-data -n openarchiver -p '{"spec":{"resources":{"requests":{"storage":"100Gi"}}}}'
```

---

## Updating Secrets

To update any secret (e.g., admin password):

```bash
./edit-sealed-secret.sh openarchiver openarchiver ADMIN_PASSWORD
```

This will:
1. Decrypt the live secret from Kubernetes
2. Open your editor with the value
3. Re-seal the secret
4. Create a new sealed secret file
5. You commit the updated file

---

## Resource Monitoring

### Memory Usage

Check resource usage:
```bash
kubectl top pods -n openarchiver
```

Expected limits:
- openarchiver: 1Gi
- valkey: 512Mi
- meilisearch: 1Gi
- tika: 2Gi

### Storage Usage

Check PVC usage:
```bash
kubectl get pvc -n openarchiver
```

---

## Removal

To remove OpenArchiver completely:

1. Delete the ArgoCD Application:
   ```bash
   kubectl delete application kustomize-openarchiver -n argocd
   ```

2. Delete the namespace:
   ```bash
   kubectl delete namespace openarchiver
   ```

3. Delete PostgreSQL user and database (if desired):
   ```bash
   kubectl exec -n postgres <postgres-pod> -- psql -U postgres -c "DROP DATABASE open_archive;"
   kubectl exec -n postgres <postgres-pod> -- psql -U postgres -c "DROP USER <openarchiver-user>;"
   ```

4. Remove files from git:
   ```bash
   git rm -r apps/openarchiver
   git rm templates/kustomize-openarchiver.yaml
   git rm scripts/generate-openarchiver-secrets.sh
   git commit -m "Remove OpenArchiver"
   git push
   ```

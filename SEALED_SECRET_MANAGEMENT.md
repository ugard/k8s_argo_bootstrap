# Sealed Secret Management Scripts

## Scripts

### view-secret-key.sh
View the decrypted value of a key from a Kubernetes secret.

```bash
./view-secret-key.sh <namespace> <secret-name> [key]
```

**Examples:**
```bash
# View gitea app.ini
./view-secret-key.sh gitea gitea app.ini

# View drone RPC secret
./view-secret-key.sh drone drone DRONE_RPC_SECRET

# List all keys in a secret
./view-secret-key.sh gitea gitea invalid-key
```

### edit-sealed-secret.sh
Edit a key in a Kubernetes secret and generate a new sealed secret.

```bash
./edit-sealed-secret.sh <namespace> <secret-name> [key]
```

**Examples:**
```bash
# Edit gitea app.ini
./edit-sealed-secret.sh gitea gitea app.ini

# Edit drone RPC secret
./edit-sealed-secret.sh drone drone DRONE_RPC_SECRET
```

**How it works:**
1. Retrieves the current secret from Kubernetes
2. Decodes the specified key
3. Opens your default editor (`$EDITOR`, defaults to `vim`)
4. Shows you the changes and asks for confirmation
5. Updates the secret in Kubernetes
6. Creates a new sealed secret file: `{secret-name}.sealed.yaml`
7. You commit the sealed secret to git

**Requirements:**
- `kubectl` configured with cluster access
- `jq` for JSON processing
- `kubeseal` for creating sealed secrets
- Text editor (vim, nano, etc.)

## Workflow

### To edit app.ini in gitea secret:

```bash
# 1. View current content (optional)
./view-secret-key.sh gitea gitea app.ini

# 2. Edit the secret
./edit-sealed-secret.sh gitea gitea app.ini

# 3. Review the generated sealed secret
cat gitea.sealed.yaml

# 4. Replace the old sealed secret file
cp gitea.sealed.yaml apps/gitea/sealed_secret.yaml

# 5. Commit and push
git add apps/gitea/sealed_secret.yaml
git commit -m "Update gitea app.ini"
git push
```

### To edit other secrets:

```bash
# Example: Update drone RPC secret
./edit-sealed-secret.sh drone drone DRONE_RPC_SECRET
cp drone.sealed.yaml apps/drone/sealed-secret.yaml
git add apps/drone/sealed-secret.yaml
git commit -m "Update drone RPC secret"
git push
```

## Notes

- Sealed secrets are encrypted and cannot be edited directly
- These scripts work by decrypting the live secret from Kubernetes
- The sealed-secrets controller automatically decrypts sealed secrets into regular secrets
- Always verify the generated sealed secret before committing
- Keep your sealed secret private key secure (sealed-secrets controller does this automatically)

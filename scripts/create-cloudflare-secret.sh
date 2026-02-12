#!/bin/bash

# Script to create SealedSecret for Cloudflare API token
# This script assumes you have kubeseal installed and access to your cluster

set -e

echo "Cloudflare SealedSecret Generator for cert-manager"
echo "=================================================="
echo

# Check if kubeseal is installed
if ! command -v kubeseal &> /dev/null; then
    echo "Error: kubeseal is not installed."
    echo "Install kubeseal from: https://github.com/bitnami-labs/sealed-secrets"
    exit 1
fi

# Prompt for Cloudflare API token
read -s -p "Enter your Cloudflare API token: " CLOUDFLARE_TOKEN
echo
echo

if [ -z "$CLOUDFLARE_TOKEN" ]; then
    echo "Error: Cloudflare API token cannot be empty."
    exit 1
fi

# Create temporary secret
cat > /tmp/cloudflare-secret.yaml << EOF
apiVersion: v1
kind: Secret
metadata:
  name: cloudflare-secret
  namespace: cert-manager2
type: Opaque
stringData:
  api-token: $CLOUDFLARE_TOKEN
EOF

echo "Creating SealedSecret..."
echo "Note: This requires access to your Kubernetes cluster with Sealed Secrets installed."
echo

# Seal the secret
kubeseal --format yaml --controller-name sealed-secrets-controller --controller-namespace kube-system < /tmp/cloudflare-secret.yaml > apps/cert-manager/cloudflare-secret.yaml

# Clean up temporary file
rm /tmp/cloudflare-secret.yaml

echo "SealedSecret created successfully: apps/cert-manager/cloudflare-secret.yaml"
echo
echo "Next steps:"
echo "1. Review the generated SealedSecret file"
echo "2. Commit and push the changes"
echo "3. The ClusterIssuer will be available after ArgoCD syncs"
#!/bin/bash

# Script to create SealedSecret for Cloudflared tunnel credentials
# This script assumes you have kubeseal installed and access to your cluster

set -e

echo "Cloudflared SealedSecret Generator"
echo "==================================="
echo

# Check if kubeseal is installed
if ! command -v kubeseal &> /dev/null; then
    echo "Error: kubeseal is not installed."
    echo "Install kubeseal from: https://github.com/bitnami-labs/sealed-secrets"
    exit 1
fi

# Default file paths
DEFAULT_JSON_FILE="$HOME/.cloudflared/manyfold-tunnel.json"
DEFAULT_PEM_FILE="$HOME/.cloudflared/cert.pem"

# Prompt for file paths with defaults
read -p "Enter path to tunnel JSON file [$DEFAULT_JSON_FILE]: " JSON_FILE
JSON_FILE=${JSON_FILE:-$DEFAULT_JSON_FILE}

read -p "Enter path to cert PEM file [$DEFAULT_PEM_FILE]: " PEM_FILE
PEM_FILE=${PEM_FILE:-$DEFAULT_PEM_FILE}

# Check if files exist
if [ ! -f "$JSON_FILE" ]; then
    echo "Error: JSON file $JSON_FILE does not exist."
    exit 1
fi

if [ ! -f "$PEM_FILE" ]; then
    echo "Error: PEM file $PEM_FILE does not exist."
    exit 1
fi

echo
echo "Processing files..."
echo "JSON file: $JSON_FILE"
echo "PEM file: $PEM_FILE"
echo

# Base64 encode the file contents
JSON_B64=$(base64 -w 0 < "$JSON_FILE")
PEM_B64=$(base64 -w 0 < "$PEM_FILE")

if [ -z "$JSON_B64" ] || [ -z "$PEM_B64" ]; then
    echo "Error: Failed to base64 encode files."
    exit 1
fi

# Create temporary secrets YAML
cat > /tmp/cloudflared-config-secret.yaml << EOF
apiVersion: v1
kind: Secret
metadata:
  name: cloudflared-config-json
  namespace: cloudflared
type: Opaque
data:
  credentials.json: $JSON_B64
EOF

cat > /tmp/cloudflared-cert-secret.yaml << EOF
apiVersion: v1
kind: Secret
metadata:
  name: cloudflared-cert-pem
  namespace: cloudflared
type: Opaque
data:
  cert.pem: $PEM_B64
EOF

echo "Creating SealedSecrets..."
echo "Note: This requires access to your Kubernetes cluster with Sealed Secrets installed."
echo

# Seal the secrets
kubeseal --format yaml --controller-name sealed-secrets-controller --controller-namespace kube-system < /tmp/cloudflared-config-secret.yaml > apps/cloudflared/sealed_secret_config.yaml
kubeseal --format yaml --controller-name sealed-secrets-controller --controller-namespace kube-system < /tmp/cloudflared-cert-secret.yaml > apps/cloudflared/sealed_secret_cert.yaml

# Clean up temporary files
rm /tmp/cloudflared-config-secret.yaml /tmp/cloudflared-cert-secret.yaml

echo "SealedSecrets created successfully:"
echo "  - apps/cloudflared/sealed_secret_config.yaml"
echo "  - apps/cloudflared/sealed_secret_cert.yaml"
echo
echo "Next steps:"
echo "1. Review the generated SealedSecret files"
echo "2. Commit and push the changes"
echo "3. The ArgoCD app will deploy cloudflared using the secrets after sync"
#!/bin/bash

set -e

NAMESPACE="${1:-gitea}"
SECRET_NAME="${2:-gitea}"
KEY="${3:-app.ini}"

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 <namespace> <secret-name> [key]"
    echo "Example: $0 gitea gitea app.ini"
    exit 1
fi

echo "Retrieving key '$KEY' from secret '$SECRET_NAME' in namespace '$NAMESPACE'..."

# Get the secret value using jq to handle special characters
SECRET_VALUE=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o json | jq -r ".data[\"$KEY\"]")

if [ -z "$SECRET_VALUE" ] || [ "$SECRET_VALUE" == "null" ]; then
    echo "Error: Key '$KEY' not found in secret '$SECRET_NAME'"
    echo "Available keys:"
    kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o json | jq -r '.data | keys[]' | sed 's/^/  - /'
    exit 1
fi

# Decode and display
echo "$SECRET_VALUE" | base64 -d

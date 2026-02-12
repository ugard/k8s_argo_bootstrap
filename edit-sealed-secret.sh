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

echo "Retrieving secret: $SECRET_NAME in namespace: $NAMESPACE"

# Get the secret and decode the key using jq to handle special characters
SECRET_VALUE=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o json | jq -r ".data[\"$KEY\"]")

if [ -z "$SECRET_VALUE" ] || [ "$SECRET_VALUE" == "null" ]; then
    echo "Error: Key '$KEY' not found in secret '$SECRET_NAME'"
    echo "Available keys:"
    kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o json | jq -r '.data | keys[]' | sed 's/^/  - /'
    exit 1
fi

# Decode to a temp file
TEMP_FILE=$(mktemp)
echo "$SECRET_VALUE" | base64 -d > "$TEMP_FILE"

echo "Current content of $KEY:"
echo "---"
cat "$TEMP_FILE"
echo "---"

# Edit the file
echo ""
echo "Opening editor to edit $KEY..."
${EDITOR:-vim} "$TEMP_FILE"

# Confirm changes
echo ""
echo "Updated content:"
echo "---"
cat "$TEMP_FILE"
echo "---"
echo ""

read -p "Do you want to update the secret and create a new sealed secret? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    rm -f "$TEMP_FILE"
    echo "Cancelled."
    exit 0
fi

# Encode the new content
ENCODED_VALUE=$(cat "$TEMP_FILE" | base64 -w 0)

# Create a patch for the secret
PATCH="[{\"op\": \"replace\", \"path\": \"/data/$KEY\", \"value\": \"$ENCODED_VALUE\"}]"

# Apply the patch to the existing secret
echo "Updating secret..."
kubectl patch secret "$SECRET_NAME" -n "$NAMESPACE" --type=json -p="$PATCH"

# Get the updated secret and create a new sealed secret
echo "Creating new sealed secret..."
SECRET_JSON=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o json | jq "del(.metadata.annotations,.metadata.creationTimestamp,.metadata.managedFields,.metadata.resourceVersion,.metadata.uid,.status)")

echo "$SECRET_JSON" | kubeseal > "${SECRET_NAME}.sealed.yaml"

echo ""
echo "✓ Secret updated successfully"
echo "✓ New sealed secret created: ${SECRET_NAME}.sealed.yaml"
echo ""
echo "Next steps:"
echo "1. Review the generated sealed secret file"
echo "2. Commit and push the file to your git repository"
echo "3. ArgoCD will sync the changes automatically"

rm -f "$TEMP_FILE"

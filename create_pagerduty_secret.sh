#!/bin/bash

# Script to create a SealedSecret for PagerDuty integration key
# Usage: ./create_pagerduty_secret.sh <integration_key>

set -e

if [ $# -ne 1 ]; then
  echo "Usage: $0 <pagerduty_integration_key>"
  exit 1
fi

INTEGRATION_KEY=$1
SECRET_NAME="pagerduty-service-key"
NAMESPACE="monitoring"

# Check if kubeseal is installed, install if not
if ! command -v kubeseal &> /dev/null; then
  echo "kubeseal not found, installing..."
  KUBESEAL_VERSION=$(curl -s https://api.github.com/repos/bitnami-labs/sealed-secrets/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
  wget -q "https://github.com/bitnami-labs/sealed-secrets/releases/download/${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION#v}-linux-amd64.tar.gz"
  tar -xf kubeseal-${KUBESEAL_VERSION#v}-linux-amd64.tar.gz
  sudo mv kubeseal /usr/local/bin/
  rm kubeseal-${KUBESEAL_VERSION#v}-linux-amd64.tar.gz
fi

# Create temporary secret YAML
cat > temp_secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: $SECRET_NAME
  namespace: $NAMESPACE
type: Opaque
data:
  service_key: $(echo -n "$INTEGRATION_KEY" | base64)
EOF

# Seal the secret
kubeseal --format yaml < temp_secret.yaml > sealedsecret_pagerduty.yaml

# Apply the SealedSecret
kubectl apply -f sealedsecret_pagerduty.yaml

# Clean up
rm temp_secret.yaml sealedsecret_pagerduty.yaml

echo "SealedSecret for PagerDuty created in namespace $NAMESPACE"
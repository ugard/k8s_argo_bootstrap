#!/bin/bash

set -e

echo "OpenArchiver SealedSecret Generator"
echo "===================================="
echo

if ! command -v kubeseal &> /dev/null; then
    echo "Error: kubeseal is not installed."
    echo "Install kubeseal from: https://github.com/bitnami-labs/sealed-secrets"
    exit 1
fi

POSTGRES_DB="open_archive"
POSTGRES_USER="openarchiver_$(openssl rand -hex 8)"
POSTGRES_PASSWORD="$(openssl rand -base64 32 | tr -d '=+/' | cut -c1-32)"
JWT_SECRET="$(openssl rand -hex 32)"
ENCRYPTION_KEY="$(openssl rand -hex 32)"
STORAGE_ENCRYPTION_KEY="$(openssl rand -hex 32)"
REDIS_PASSWORD="$(openssl rand -base64 24 | tr -d '=+/' | cut -c1-20)"
MEILI_MASTER_KEY="$(openssl rand -base64 32 | tr -d '=+/' | cut -c1-32)"
APP_URL="https://openarchiver.ugard.win"
ADMIN_USERNAME="admin@local.com"
ADMIN_PASSWORD="$(openssl rand -base64 32 | tr -d '=+/' | cut -c1-24)"

DATABASE_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres.postgres:5432/${POSTGRES_DB}"

echo "Generated secrets:"
echo "  POSTGRES_DB: ${POSTGRES_DB}"
echo "  POSTGRES_USER: ${POSTGRES_USER}"
echo "  POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}"
echo "  DATABASE_URL: ${DATABASE_URL}"
echo "  JWT_SECRET: ${JWT_SECRET}"
echo "  ENCRYPTION_KEY: ${ENCRYPTION_KEY}"
echo "  STORAGE_ENCRYPTION_KEY: ${STORAGE_ENCRYPTION_KEY}"
echo "  REDIS_PASSWORD: ${REDIS_PASSWORD}"
echo "  MEILI_MASTER_KEY: ${MEILI_MASTER_KEY}"
echo "  APP_URL: ${APP_URL}"
echo "  ADMIN_USERNAME: ${ADMIN_USERNAME}"
echo "  ADMIN_PASSWORD: ${ADMIN_PASSWORD}"
echo
echo "IMPORTANT: Save these values securely. They will not be shown again."
echo
read -p "Press Enter to continue or Ctrl+C to cancel..."

cat > /tmp/openarchiver-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: openarchiver
  namespace: openarchiver
type: Opaque
stringData:
  POSTGRES_DB: ${POSTGRES_DB}
  POSTGRES_USER: ${POSTGRES_USER}
  POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
  DATABASE_URL: ${DATABASE_URL}
  JWT_SECRET: ${JWT_SECRET}
  ENCRYPTION_KEY: ${ENCRYPTION_KEY}
  STORAGE_ENCRYPTION_KEY: ${STORAGE_ENCRYPTION_KEY}
  REDIS_PASSWORD: ${REDIS_PASSWORD}
  MEILI_MASTER_KEY: ${MEILI_MASTER_KEY}
  APP_URL: ${APP_URL}
  ADMIN_USERNAME: ${ADMIN_USERNAME}
  ADMIN_PASSWORD: ${ADMIN_PASSWORD}
EOF

echo "Creating SealedSecret..."
echo "Note: This requires access to your Kubernetes cluster with Sealed Secrets installed."
echo

kubeseal --format yaml --controller-name sealed-secrets-controller --controller-namespace kube-system < /tmp/openarchiver-secret.yaml > apps/openarchiver/openarchiver.sealed_secret.yaml

rm /tmp/openarchiver-secret.yaml

echo "SealedSecret created successfully: apps/openarchiver/openarchiver.sealed_secret.yaml"
echo
echo "Next steps:"
echo "1. Review the generated SealedSecret file"
echo "2. Run: chmod +x scripts/generate-openarchiver-secrets.sh"
echo "3. Commit and push the changes"
echo "4. The ArgoCD app will deploy OpenArchiver after sync"
echo
echo "After deployment:"
echo "1. Access https://openarchiver.ugard.win"
echo "2. Login with username: ${ADMIN_USERNAME}"
echo "3. Password: ${ADMIN_PASSWORD}"
echo "4. Change to a secure password immediately"

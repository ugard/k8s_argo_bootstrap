#!/bin/bash
set -e

# Configuration
NAMESPACE="rtorrent"
SECRET_NAME="sonarr-postgres"
POSTGRES_NAMESPACE="postgres"
POSTGRES_USER="sonarr"
POSTGRES_MAIN_DB="sonarr-main"
POSTGRES_LOG_DB="sonarr-log"

echo "Finding PostgreSQL pod..."
POSTGRES_POD=$(kubectl get pods -n $POSTGRES_NAMESPACE -l app=postgres -o jsonpath='{.items[0].metadata.name}')

if [ -z "$POSTGRES_POD" ]; then
    echo "Error: PostgreSQL pod not found in namespace $POSTGRES_NAMESPACE"
    exit 1
fi

echo "Found PostgreSQL pod: ${POSTGRES_POD}"

# Generate random password
POSTGRES_PASSWORD="$(openssl rand -base64 32 | tr -d '=+/' | cut -c1-32)"

echo "Creating databases and user in PostgreSQL..."

# Create databases
kubectl exec -n $POSTGRES_NAMESPACE "${POSTGRES_POD}" -- psql -U postgres -c "CREATE DATABASE \"${POSTGRES_MAIN_DB}\";" 2>/dev/null || echo "Database ${POSTGRES_MAIN_DB} may already exist."
kubectl exec -n $POSTGRES_NAMESPACE "${POSTGRES_POD}" -- psql -U postgres -c "CREATE DATABASE \"${POSTGRES_LOG_DB}\";" 2>/dev/null || echo "Database ${POSTGRES_LOG_DB} may already exist."

# Create user and grant privileges
kubectl exec -n $POSTGRES_NAMESPACE "${POSTGRES_POD}" -- psql -U postgres -c "CREATE USER ${POSTGRES_USER} WITH PASSWORD '${POSTGRES_PASSWORD}';" 2>/dev/null || \
    kubectl exec -n $POSTGRES_NAMESPACE "${POSTGRES_POD}" -- psql -U postgres -c "ALTER USER ${POSTGRES_USER} WITH PASSWORD '${POSTGRES_PASSWORD}';"

kubectl exec -n $POSTGRES_NAMESPACE "${POSTGRES_POD}" -- psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE \"${POSTGRES_MAIN_DB}\" TO ${POSTGRES_USER};"
kubectl exec -n $POSTGRES_NAMESPACE "${POSTGRES_POD}" -- psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE \"${POSTGRES_LOG_DB}\" TO ${POSTGRES_USER};"

# For Sonarr v4, we need to ensure the user has permissions on the public schema
kubectl exec -n $POSTGRES_NAMESPACE "${POSTGRES_POD}" -- psql -U postgres -d "${POSTGRES_MAIN_DB}" -c "GRANT ALL ON SCHEMA public TO ${POSTGRES_USER};"
kubectl exec -n $POSTGRES_NAMESPACE "${POSTGRES_POD}" -- psql -U postgres -d "${POSTGRES_LOG_DB}" -c "GRANT ALL ON SCHEMA public TO ${POSTGRES_USER};"

echo "Database setup complete."

# Generate temporary secret file for sealing
cat <<EOF > sonarr-postgres-temp.yaml
apiVersion: v1
kind: Secret
metadata:
  name: ${SECRET_NAME}
  namespace: ${NAMESPACE}
type: Opaque
stringData:
  password: ${POSTGRES_PASSWORD}
EOF

echo ""
echo "------------------------------------------------------------"
echo "DONE! PostgreSQL is ready for Sonarr."
echo ""
echo "Now run the following command to create the SealedSecret:"
echo ""
echo "kubeseal --format=yaml < sonarr-postgres-temp.yaml > apps/rtorrent/sonarr-postgres.sealed_secret.yaml"
echo ""
echo "After that, delete the temporary file:"
echo "rm sonarr-postgres-temp.yaml"
echo "------------------------------------------------------------"

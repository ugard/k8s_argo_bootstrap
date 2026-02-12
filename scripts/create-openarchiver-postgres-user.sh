#!/bin/bash

set -e

echo "OpenArchiver PostgreSQL User & Database Setup"
echo "=============================================="
echo

if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl is not installed or not configured."
    exit 1
fi

POSTGRES_POD=$(kubectl get pods -n postgres -l app=postgres -o jsonpath='{.items[0].metadata.name}')

if [ -z "$POSTGRES_POD" ]; then
    echo "Error: PostgreSQL pod not found in 'postgres' namespace."
    echo "Make sure the shared postgres is running."
    exit 1
fi

echo "Found PostgreSQL pod: ${POSTGRES_POD}"
echo

echo "Choose an option:"
echo "  1) Generate random username and password"
echo "  2) Enter custom username and password"
echo
read -p "Select option [1-2]: " OPTION

if [ "$OPTION" = "1" ]; then
    POSTGRES_USER="openarchiver_$(openssl rand -hex 8)"
    POSTGRES_PASSWORD="$(openssl rand -base64 32 | tr -d '=+/' | cut -c1-32)"
elif [ "$OPTION" = "2" ]; then
    read -p "Enter database name [open_archive]: " POSTGRES_DB
    POSTGRES_DB=${POSTGRES_DB:-open_archive}

    read -p "Enter username: " POSTGRES_USER
    if [ -z "$POSTGRES_USER" ]; then
        echo "Error: Username cannot be empty."
        exit 1
    fi

    read -s -p "Enter password: " POSTGRES_PASSWORD
    echo
    if [ -z "$POSTGRES_PASSWORD" ]; then
        echo "Error: Password cannot be empty."
        exit 1
    fi
else
    echo "Invalid option."
    exit 1
fi

POSTGRES_DB="open_archive"

echo
echo "Configuration:"
echo "  Database: ${POSTGRES_DB}"
echo "  Username: ${POSTGRES_USER}"
echo "  Password: ${POSTGRES_PASSWORD}"
echo
read -p "Proceed? [y/N]: " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

echo
echo "Creating database and user..."
echo

kubectl exec -n postgres "${POSTGRES_POD}" -- psql -U postgres -c "CREATE DATABASE ${POSTGRES_DB};" 2>/dev/null || echo "Database may already exist, continuing..."

kubectl exec -n postgres "${POSTGRES_POD}" -- psql -U postgres -c "CREATE USER ${POSTGRES_USER} WITH PASSWORD '${POSTGRES_PASSWORD}';" 2>/dev/null || echo "User may already exist, will update password..."

kubectl exec -n postgres "${POSTGRES_POD}" -- psql -U postgres -c "ALTER USER ${POSTGRES_USER} WITH PASSWORD '${POSTGRES_PASSWORD}';"

kubectl exec -n postgres "${POSTGRES_POD}" -- psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE ${POSTGRES_DB} TO ${POSTGRES_USER};"

echo
echo "Database setup completed successfully!"
echo
echo "Connection string for DATABASE_URL:"
echo "  postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres.postgres:5432/${POSTGRES_DB}"
echo
echo "IMPORTANT: Save these credentials securely!"

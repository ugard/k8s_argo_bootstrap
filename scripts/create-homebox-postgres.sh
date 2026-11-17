#!/bin/bash
# Zakłada bazę i użytkownika homebox we współdzielonym postgresie i generuje
# apps/homebox/sealed_secret.yaml. Hasło nie trafia na dysk w postaci jawnej.

set -euo pipefail

DB="homebox"
DB_USER="homebox"
OUT="$(dirname "$0")/../apps/homebox/sealed_secret.yaml"

POSTGRES_POD=$(kubectl get pods -n postgres -l app=postgres -o jsonpath='{.items[0].metadata.name}')
if [[ -z "$POSTGRES_POD" ]]; then
    echo "Nie znaleziono poda postgres w namespace postgres." >&2
    exit 1
fi

PASSWORD="$(openssl rand -base64 48 | tr -d '=+/' | cut -c1-32)"

psql_postgres() {
    kubectl exec -i -n postgres "$POSTGRES_POD" -- psql -v ON_ERROR_STOP=1 -U postgres "$@"
}

if psql_postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname = '${DB_USER}'" | grep -q 1; then
    echo "Użytkownik ${DB_USER} istnieje - ustawiam nowe hasło."
    psql_postgres -c "ALTER ROLE ${DB_USER} WITH LOGIN PASSWORD '${PASSWORD}';" >/dev/null
else
    psql_postgres -c "CREATE ROLE ${DB_USER} WITH LOGIN PASSWORD '${PASSWORD}';" >/dev/null
fi

if ! psql_postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '${DB}'" | grep -q 1; then
    # właściciel bazy = homebox, żeby miał prawa do schematu public (PG15+)
    psql_postgres -c "CREATE DATABASE ${DB} OWNER ${DB_USER};" >/dev/null
fi

kubectl create secret generic homebox -n homebox --dry-run=client -o yaml \
    --from-literal=HBOX_DATABASE_USERNAME="$DB_USER" \
    --from-literal=HBOX_DATABASE_PASSWORD="$PASSWORD" \
    | kubeseal --format yaml > "$OUT"

echo "Gotowe: baza ${DB}, użytkownik ${DB_USER}, ${OUT}"

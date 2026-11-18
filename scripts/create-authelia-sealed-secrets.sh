#!/bin/bash
# Zakłada bazy i użytkowników authelia + lldap we współdzielonym postgresie
# i generuje:
#   apps/authelia/sealed_secret_authelia.yaml
#   apps/authelia/sealed_secret_lldap.yaml
# Sekrety nie trafiają na dysk w postaci jawnej.
#
# UWAGA - ponowne uruchomienie (--force) rotuje WSZYSTKO:
#   - STORAGE_ENCRYPTION_KEY: Authelia nie odczyta zaszyfrowanych danych
#     (zarejestrowane passkeye/TOTP do ponownej rejestracji, trzeba też wyczyścić
#     bazę authelia albo użyć `authelia storage encryption change-key`),
#   - LLDAP_LDAP_USER_PASS: LLDAP ustawia je tylko przy pierwszym starcie,
#     więc po rotacji trzeba ręcznie zmienić hasło admina w UI na nowe,
#   - LLDAP_KEY_SEED/JWT: wylogowuje sesje LLDAP.

set -euo pipefail

NS="authelia"
DIR="$(dirname "$0")/../apps/authelia"
OUT_AUTHELIA="${DIR}/sealed_secret_authelia.yaml"
OUT_LLDAP="${DIR}/sealed_secret_lldap.yaml"

if [[ "${1:-}" != "--force" ]] && [[ -e "$OUT_AUTHELIA" || -e "$OUT_LLDAP" ]]; then
    echo "Sealed secrety już istnieją - uruchom z --force, jeśli na pewno chcesz je zrotować (patrz nagłówek skryptu)." >&2
    exit 1
fi

POSTGRES_POD=$(kubectl get pods -n postgres -l app=postgres -o jsonpath='{.items[0].metadata.name}')
if [[ -z "$POSTGRES_POD" ]]; then
    echo "Nie znaleziono poda postgres w namespace postgres." >&2
    exit 1
fi

rand() {
    local len="$1"
    openssl rand -base64 $((len * 2)) | tr -d '=+/\n' | cut -c1-"$len"
}

psql_postgres() {
    kubectl exec -i -n postgres "$POSTGRES_POD" -- psql -v ON_ERROR_STOP=1 -U postgres "$@"
}

ensure_db() {
    local db="$1"
    local password="$2"

    if psql_postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname = '${db}'" | grep -q 1; then
        echo "Użytkownik ${db} istnieje - ustawiam nowe hasło."
        psql_postgres -c "ALTER ROLE ${db} WITH LOGIN PASSWORD '${password}';" >/dev/null
    else
        psql_postgres -c "CREATE ROLE ${db} WITH LOGIN PASSWORD '${password}';" >/dev/null
    fi

    if ! psql_postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '${db}'" | grep -q 1; then
        # właściciel bazy = użytkownik aplikacji, żeby miał prawa do schematu public (PG15+)
        psql_postgres -c "CREATE DATABASE ${db} OWNER ${db};" >/dev/null
    fi
}

AUTHELIA_DB_PASSWORD="$(rand 32)"
LLDAP_DB_PASSWORD="$(rand 32)"
# hasło konta serwisowego uid=authelia w LLDAP (zakłada je job lldap-bootstrap)
LDAP_BIND_PASSWORD="$(rand 48)"

ensure_db authelia "$AUTHELIA_DB_PASSWORD"
ensure_db lldap "$LLDAP_DB_PASSWORD"

kubectl create secret generic authelia -n "$NS" --dry-run=client -o yaml \
    --from-literal=RESET_PASSWORD_JWT_SECRET="$(rand 64)" \
    --from-literal=SESSION_SECRET="$(rand 64)" \
    --from-literal=STORAGE_ENCRYPTION_KEY="$(rand 64)" \
    --from-literal=STORAGE_PASSWORD="$AUTHELIA_DB_PASSWORD" \
    --from-literal=LDAP_PASSWORD="$LDAP_BIND_PASSWORD" \
    --from-literal=OIDC_HMAC_SECRET="$(rand 64)" \
    --from-literal=OIDC_JWKS_KEY="$(openssl genrsa 4096 2>/dev/null)" \
    | kubeseal --format yaml > "$OUT_AUTHELIA"

kubectl create secret generic lldap -n "$NS" --dry-run=client -o yaml \
    --from-literal=LLDAP_JWT_SECRET="$(rand 64)" \
    --from-literal=LLDAP_KEY_SEED="$(rand 64)" \
    --from-literal=LLDAP_LDAP_USER_PASS="$(rand 32)" \
    --from-literal=LLDAP_DATABASE_URL="postgres://lldap:${LLDAP_DB_PASSWORD}@postgres.postgres.svc.cluster.local/lldap" \
    | kubeseal --format yaml > "$OUT_LLDAP"

echo "Gotowe: bazy authelia + lldap, ${OUT_AUTHELIA}, ${OUT_LLDAP}"
echo "Hasło admina LLDAP po deployu: ./view-secret-key.sh ${NS} lldap LLDAP_LDAP_USER_PASS"

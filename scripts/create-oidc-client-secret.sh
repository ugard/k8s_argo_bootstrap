#!/bin/bash
# Generuje sekret klienta OIDC dla Authelii i zapisuje go w dwóch miejscach:
#   - digest (pbkdf2-sha512) -> klucz OIDC_CLIENT_<ID>_DIGEST w
#     apps/authelia/sealed_secret_authelia.yaml (czyta go configuration.yml),
#   - jawny sekret -> <key> w secrecie <secret> aplikacji (nowy albo dopisany
#     do istniejącego sealed secretu).
# Jawny sekret nie trafia na dysk. Digest liczy działający pod Authelii.
#
# Przykład:
#   ./scripts/create-oidc-client-secret.sh grafana grafana grafana-oidc \
#       GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET apps/grafana/sealed_secret_oidc.yaml
#
# Ponowne uruchomienie rotuje sekret - trzeba zsynchronizować obie aplikacje.

set -euo pipefail

if [[ $# -ne 5 ]]; then
    echo "Użycie: $0 <client_id> <namespace> <secret> <key> <sealed_secret_file>" >&2
    exit 1
fi

CLIENT_ID="$1"
APP_NS="$2"
APP_SECRET="$3"
APP_KEY="$4"
APP_FILE="$5"

ROOT="$(dirname "$0")/.."
AUTHELIA_FILE="${ROOT}/apps/authelia/sealed_secret_authelia.yaml"
DIGEST_KEY="OIDC_CLIENT_$(echo "$CLIENT_ID" | tr '[:lower:]-' '[:upper:]_')_DIGEST"

CLIENT_SECRET="$(openssl rand -base64 96 | tr -d '=+/\n' | cut -c1-72)"

DIGEST="$(kubectl -n authelia exec deploy/authelia -c authelia -- \
    authelia crypto hash generate pbkdf2 --variant sha512 --password "$CLIENT_SECRET" --no-confirm \
    | sed -n 's/^Digest: //p')"
if [[ "$DIGEST" != '$pbkdf2-sha512$'* ]]; then
    echo "Nie udało się wygenerować digestu w podzie authelia." >&2
    exit 1
fi

kubectl create secret generic authelia -n authelia --dry-run=client -o json \
    --from-literal="${DIGEST_KEY}=${DIGEST}" \
    | kubeseal --merge-into "$AUTHELIA_FILE"

if [[ -f "$APP_FILE" ]]; then
    kubectl create secret generic "$APP_SECRET" -n "$APP_NS" --dry-run=client -o json \
        --from-literal="${APP_KEY}=${CLIENT_SECRET}" \
        | kubeseal --merge-into "$APP_FILE"
else
    kubectl create secret generic "$APP_SECRET" -n "$APP_NS" --dry-run=client -o yaml \
        --from-literal="${APP_KEY}=${CLIENT_SECRET}" \
        | kubeseal --format yaml > "$APP_FILE"
fi

echo "Gotowe: ${DIGEST_KEY} w ${AUTHELIA_FILE}, ${APP_KEY} w ${APP_FILE}"

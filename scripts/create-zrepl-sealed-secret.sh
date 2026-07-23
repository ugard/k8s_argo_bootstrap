#!/bin/bash

set -euo pipefail

# Generuje parę self-signed certyfikatów TLS dla zrepl (model pull):
#   - CN=prod    -> prezentowany przez SERWER (job source na i8d-hmt)
#   - CN=backups -> prezentowany przez KLIENTA (job pull na 95t-m8m)
# Oba z EKU serverAuth+clientAuth, bo po odwróceniu ról (push->pull) każdy
# węzeł pełni obie funkcje. Certy służą sobie nawzajem jako CA (self-signed,
# bez osobnego CA) — dokładnie jak oczekuje config w apps/benji-backup/zrepl.yaml.
# Wynik: dwa SealedSecret (zrepl-prod, zrepl-backup) w apps/benji-backup/sealed-secrets.yaml.

APP_DIR="apps/benji-backup"
KUSTOMIZATION_FILE="${APP_DIR}/kustomization.yaml"
OUTPUT_FILE="${APP_DIR}/sealed-secrets.yaml"
NAMESPACE="backup-system"
DAYS="${ZREPL_CERT_DAYS:-3650}"
CONTROLLER_NAME="${SEALED_SECRETS_CONTROLLER_NAME:-sealed-secrets-controller}"
CONTROLLER_NAMESPACE="${SEALED_SECRETS_CONTROLLER_NAMESPACE:-kube-system}"
KUBECTL_CONTEXT="${KUBECTL_CONTEXT:-}"

for bin in openssl kubectl kubeseal; do
    if ! command -v "$bin" &> /dev/null; then
        echo "Error: $bin is not installed." >&2
        [[ "$bin" == "kubeseal" ]] && echo "Install: https://github.com/bitnami-labs/sealed-secrets" >&2
        exit 1
    fi
done

if [[ ! -f "$KUSTOMIZATION_FILE" ]]; then
    echo "Error: Missing file: $KUSTOMIZATION_FILE" >&2
    exit 1
fi

echo "zrepl TLS SealedSecret generator (pull model)"
echo "============================================="
echo ""
echo "Wygeneruje NOWE certy CN=prod (serwer/source) i CN=backups (klient/pull),"
echo "oba serverAuth+clientAuth, ważne ${DAYS} dni. Nadpisze ${OUTPUT_FILE}."
echo ""
read -r -p "Kontynuować? [y/N]: " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

KUBECTL_ARGS=()
if [[ -n "$KUBECTL_CONTEXT" ]]; then
    KUBECTL_ARGS+=(--context "$KUBECTL_CONTEXT")
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

gen_cert() {
    local cn="$1"
    openssl req -x509 -newkey rsa:4096 -nodes \
        -keyout "${WORKDIR}/${cn}.key" \
        -out "${WORKDIR}/${cn}.crt" \
        -days "$DAYS" \
        -subj "/CN=${cn}" \
        -addext "subjectAltName=DNS:${cn}" \
        -addext "keyUsage=digitalSignature,keyEncipherment" \
        -addext "extendedKeyUsage=serverAuth,clientAuth" \
        2>/dev/null
    echo "  ✓ wygenerowano cert CN=${cn} (serverAuth+clientAuth, ${DAYS}d)" >&2
}

seal() {
    local secret_name="$1" cn="$2"
    kubectl "${KUBECTL_ARGS[@]}" create secret tls "$secret_name" \
        --namespace "$NAMESPACE" \
        --cert="${WORKDIR}/${cn}.crt" \
        --key="${WORKDIR}/${cn}.key" \
        --dry-run=client -o json \
        | kubeseal --format yaml \
            --controller-name "$CONTROLLER_NAME" \
            --controller-namespace "$CONTROLLER_NAMESPACE"
}

echo ""
gen_cert prod
gen_cert backups

TMP_OUTPUT="$(mktemp)"
trap 'rm -rf "$WORKDIR"; rm -f "$TMP_OUTPUT"' EXIT

{
    seal zrepl-prod prod
    seal zrepl-backup backups
} > "$TMP_OUTPUT"

mv "$TMP_OUTPUT" "$OUTPUT_FILE"

if ! grep -q "sealed-secrets.yaml" "$KUSTOMIZATION_FILE"; then
    echo "Error: '${OUTPUT_FILE##*/}' is not referenced in ${KUSTOMIZATION_FILE}." >&2
    echo "Add the following entry under 'resources:' manually, then re-run:" >&2
    echo "  - ${OUTPUT_FILE##*/}" >&2
    exit 1
fi

echo ""
echo "✓ SealedSecrets created: ${OUTPUT_FILE} (zrepl-prod, zrepl-backup)"
echo "✓ kustomization: ${KUSTOMIZATION_FILE}"
echo ""
echo "Next steps:"
echo "1. Commit ${OUTPUT_FILE} + ${KUSTOMIZATION_FILE}"
echo "2. Push i sync: argocd app sync kustomize-benji"
echo "3. Restart podów źródła/pull (nowe certy): kubectl -n ${NAMESPACE} rollout restart ds/zrepl-garage-source ds/zrepl-garage-pull"

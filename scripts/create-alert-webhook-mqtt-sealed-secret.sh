#!/bin/bash

set -euo pipefail

APP_DIR="apps/alert-webhook"
KUSTOMIZATION_FILE="${APP_DIR}/kustomization.yaml"
OUTPUT_FILE="${APP_DIR}/sealed_secret.yaml"
NAMESPACE="monitoring"
SECRET_NAME="alert-webhook-mqtt"
CONTROLLER_NAME="${SEALED_SECRETS_CONTROLLER_NAME:-sealed-secrets-controller}"
CONTROLLER_NAMESPACE="${SEALED_SECRETS_CONTROLLER_NAMESPACE:-kube-system}"
KUBECTL_CONTEXT="${KUBECTL_CONTEXT:-}"

if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl is not installed."
    exit 1
fi

if ! command -v kubeseal &> /dev/null; then
    echo "Error: kubeseal is not installed."
    echo "Install kubeseal from: https://github.com/bitnami-labs/sealed-secrets"
    exit 1
fi

if [[ ! -f "$KUSTOMIZATION_FILE" ]]; then
    echo "Error: Missing file: $KUSTOMIZATION_FILE"
    exit 1
fi

echo "alert-webhook-mqtt SealedSecret generator"
echo "=========================================="
echo ""
echo "Podaj hasło użytkownika 'alert-webhook' brokera mqtt-internal"
echo "(to samo, które trafiło do sekretu mosquitto-credentials —"
echo " scripts/create-mqtt-internal-sealed-secret.sh)."
echo ""

MQTT_PASSWORD=""
while [[ -z "$MQTT_PASSWORD" ]]; do
    read -r -s -p "MQTT_PASSWORD: " MQTT_PASSWORD
    echo
    MQTT_PASSWORD="${MQTT_PASSWORD#"${MQTT_PASSWORD%%[![:space:]]*}"}"
    MQTT_PASSWORD="${MQTT_PASSWORD%"${MQTT_PASSWORD##*[![:space:]]}"}"
    [[ -z "$MQTT_PASSWORD" ]] && echo "Value cannot be empty."
done

echo ""
echo "SealedSecret output: ${OUTPUT_FILE}"
echo "Namespace: ${NAMESPACE}"
echo "Secret name: ${SECRET_NAME}"
echo "Controller: ${CONTROLLER_NAME} (ns: ${CONTROLLER_NAMESPACE})"
if [[ -n "$KUBECTL_CONTEXT" ]]; then
    echo "kubectl context: ${KUBECTL_CONTEXT}"
fi

echo ""
read -r -p "Wygenerować SealedSecret? [y/N]: " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

KUBECTL_ARGS=()
if [[ -n "$KUBECTL_CONTEXT" ]]; then
    KUBECTL_ARGS+=(--context "$KUBECTL_CONTEXT")
fi

TMP_OUTPUT="$(mktemp)"
trap 'rm -f "$TMP_OUTPUT"' EXIT

kubectl "${KUBECTL_ARGS[@]}" create secret generic "$SECRET_NAME" \
    --namespace "$NAMESPACE" \
    --from-literal=MQTT_PASSWORD="$MQTT_PASSWORD" \
    --dry-run=client \
    -o json \
    | kubeseal \
        --format yaml \
        --controller-name "$CONTROLLER_NAME" \
        --controller-namespace "$CONTROLLER_NAMESPACE" \
    > "$TMP_OUTPUT"

mv "$TMP_OUTPUT" "$OUTPUT_FILE"

if ! grep -q "sealed_secret.yaml" "$KUSTOMIZATION_FILE"; then
    echo "  - sealed_secret.yaml" >> "$KUSTOMIZATION_FILE"
fi

unset MQTT_PASSWORD

echo ""
echo "✓ SealedSecret created: ${OUTPUT_FILE}"
echo "✓ kustomization updated: ${KUSTOMIZATION_FILE}"
echo ""
echo "Next steps:"
echo "1. Sprawdź plik ${OUTPUT_FILE}"
echo "2. Commit: ${OUTPUT_FILE} i ${KUSTOMIZATION_FILE}"
echo "3. Push i manualny sync ArgoCD: argocd app sync alert-webhook"

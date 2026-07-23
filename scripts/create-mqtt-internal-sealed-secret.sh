#!/bin/bash

set -euo pipefail

APP_DIR="apps/mqtt-internal"
KUSTOMIZATION_FILE="${APP_DIR}/kustomization.yaml"
OUTPUT_FILE="${APP_DIR}/sealed_secret.yaml"
NAMESPACE="mqtt-internal"
SECRET_NAME="mosquitto-credentials"
CONTROLLER_NAME="${SEALED_SECRETS_CONTROLLER_NAME:-sealed-secrets-controller}"
CONTROLLER_NAMESPACE="${SEALED_SECRETS_CONTROLLER_NAMESPACE:-kube-system}"
KUBECTL_CONTEXT="${KUBECTL_CONTEXT:-}"

trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

read_password_or_generate() {
    local label="$1"
    local value=""

    read -r -s -p "${label} (puste = wygeneruj losowe): " value >&2
    echo >&2
    value="$(trim "$value")"
    if [[ -z "$value" ]]; then
        value="$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)"
        echo "  wygenerowano losowe hasło" >&2
    fi
    printf '%s' "$value"
}

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

echo "mqtt-internal (Mosquitto) SealedSecret generator"
echo "================================================"
echo ""
echo "Hasła użytkowników brokera. Te same wartości musisz podać klientom:"
echo "  - xmpp-bridge    -> secret xmpp-credentials (MQTT_PASSWORD), ns xmpp-bridge"
echo "  - alert-webhook  -> konfiguracja alert-webhook, ns monitoring"
echo ""

XMPP_BRIDGE_PASSWORD="$(read_password_or_generate "hasło użytkownika xmpp-bridge")"
ALERT_WEBHOOK_PASSWORD="$(read_password_or_generate "hasło użytkownika alert-webhook")"

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

to_base64() {
    printf '%s' "$1" | base64 | tr -d '\n'
}

generate_secret_yaml() {
    cat <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${SECRET_NAME}
  namespace: ${NAMESPACE}
type: Opaque
data:
  XMPP_BRIDGE_PASSWORD: $(to_base64 "$XMPP_BRIDGE_PASSWORD")
  ALERT_WEBHOOK_PASSWORD: $(to_base64 "$ALERT_WEBHOOK_PASSWORD")
EOF
}

TMP_OUTPUT="$(mktemp)"
trap 'rm -f "$TMP_OUTPUT"' EXIT

generate_secret_yaml \
    | kubectl "${KUBECTL_ARGS[@]}" create \
        --dry-run=client \
        -f - \
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

echo ""
echo "✓ SealedSecret created: ${OUTPUT_FILE}"
echo "✓ kustomization updated: ${KUSTOMIZATION_FILE}"
echo ""
echo "UWAGA: hasła klientów (potrzebne do sekretów xmpp-credentials i alert-webhook):"
echo "  xmpp-bridge:   ${XMPP_BRIDGE_PASSWORD}"
echo "  alert-webhook: ${ALERT_WEBHOOK_PASSWORD}"
echo "Zapisz je w menedżerze haseł — nie zostaną nigdzie zapisane jawnie."
echo ""
echo "Next steps:"
echo "1. Sprawdź plik ${OUTPUT_FILE}"
echo "2. Commit: ${OUTPUT_FILE} i ${KUSTOMIZATION_FILE}"
echo "3. Push i manualny sync ArgoCD: argocd app sync mqtt-internal"
echo "4. Przepnij mostek: scripts/create-mqtt-xmpp-bridge-sealed-secret.sh"
echo "   (MQTT_BROKER=tcp://mosquitto.mqtt-internal.svc:1883, MQTT_USERNAME=xmpp-bridge)"

unset XMPP_BRIDGE_PASSWORD ALERT_WEBHOOK_PASSWORD

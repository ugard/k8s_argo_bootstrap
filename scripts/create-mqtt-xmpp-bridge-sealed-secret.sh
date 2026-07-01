#!/bin/bash

set -euo pipefail

APP_DIR="apps/mqtt-xmpp-bridge"
KUSTOMIZATION_FILE="${APP_DIR}/kustomization.yaml"
OUTPUT_FILE="${APP_DIR}/sealed_secret.yaml"
NAMESPACE="xmpp-bridge"
SECRET_NAME="xmpp-credentials"
CONTROLLER_NAME="${SEALED_SECRETS_CONTROLLER_NAME:-sealed-secrets-controller}"
CONTROLLER_NAMESPACE="${SEALED_SECRETS_CONTROLLER_NAMESPACE:-kube-system}"
KUBECTL_CONTEXT="${KUBECTL_CONTEXT:-}"

read_required() {
    local label="$1"
    local value=""

    while true; do
        read -r -p "${label}: " value
        if [[ -n "$value" ]]; then
            printf '%s' "$value"
            return
        fi
        echo "Value cannot be empty."
    done
}

read_required_secret() {
    local label="$1"
    local value=""

    while true; do
        read -r -s -p "${label}: " value
        echo
        if [[ -n "$value" ]]; then
            printf '%s' "$value"
            return
        fi
        echo "Value cannot be empty."
    done
}

read_with_default() {
    local label="$1"
    local default_value="$2"
    local value=""

    read -r -p "${label} [${default_value}]: " value
    if [[ -z "$value" ]]; then
        printf '%s' "$default_value"
        return
    fi

    printf '%s' "$value"
}

read_yes_no_default() {
    local label="$1"
    local default_value="$2"
    local value=""
    local prompt_suffix=""

    if [[ "$default_value" == "y" ]]; then
        prompt_suffix="[Y/n]"
    else
        prompt_suffix="[y/N]"
    fi

    while true; do
        read -r -p "${label} ${prompt_suffix}: " value
        if [[ -z "$value" ]]; then
            value="$default_value"
        fi

        case "$value" in
            y|Y|yes|YES)
                printf 'y'
                return
                ;;
            n|N|no|NO)
                printf 'n'
                return
                ;;
            *)
                echo "Please answer y or n."
                ;;
        esac
    done
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

echo "mqtt-xmpp-bridge SealedSecret generator"
echo "========================================"
echo ""
echo "Podaj wartości. Hasła nie będą wyświetlane i nie zostaną zapisane w postaci jawnej do plików."
echo ""

XMPP_JID="$(read_required "XMPP_JID (np. bot@xmpp.jp)")"
XMPP_PASSWORD="$(read_required_secret "XMPP_PASSWORD")"
ALERTS_ROOM_PASSWORD="$(read_required_secret "ALERTS_ROOM_PASSWORD")"
PRINTER_ROOM_PASSWORD="$(read_required_secret "PRINTER_ROOM_PASSWORD")"
XIYOHE_ROOM_PASSWORD="$(read_required_secret "XIYOHE_ROOM_PASSWORD (hasło pokoju xiyohe@conference.xmpp.jp)")"
MQTT_ANONYMOUS="$(read_yes_no_default "MQTT anonymous auth (brak login/hasło)" "n")"
if [[ "$MQTT_ANONYMOUS" == "y" ]]; then
    MQTT_USERNAME=""
    MQTT_PASSWORD=""
else
    MQTT_USERNAME="$(read_with_default "MQTT_USERNAME" "xmpp-bridge")"
    MQTT_PASSWORD="$(read_required_secret "MQTT_PASSWORD")"
fi
MQTT_BROKER="$(read_required "MQTT_BROKER (np. tcp://mosquitto-mqtt.hass.svc:1883)")"
CLUSTER_NAME="$(read_with_default "CLUSTER_NAME" "default")"

echo ""
echo "SealedSecret output: ${OUTPUT_FILE}"
echo "Namespace: ${NAMESPACE}"
echo "Secret name: ${SECRET_NAME}"
echo "Controller: ${CONTROLLER_NAME} (ns: ${CONTROLLER_NAMESPACE})"
if [[ "$MQTT_ANONYMOUS" == "y" ]]; then
    echo "MQTT auth mode: anonymous"
else
    echo "MQTT auth mode: username/password"
fi
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
  XMPP_JID: $(to_base64 "$XMPP_JID")
  XMPP_PASSWORD: $(to_base64 "$XMPP_PASSWORD")
  ALERTS_ROOM_PASSWORD: $(to_base64 "$ALERTS_ROOM_PASSWORD")
  PRINTER_ROOM_PASSWORD: $(to_base64 "$PRINTER_ROOM_PASSWORD")
  XIYOHE_ROOM_PASSWORD: $(to_base64 "$XIYOHE_ROOM_PASSWORD")
  MQTT_USERNAME: $(to_base64 "$MQTT_USERNAME")
  MQTT_PASSWORD: $(to_base64 "$MQTT_PASSWORD")
  MQTT_BROKER: $(to_base64 "$MQTT_BROKER")
  CLUSTER_NAME: $(to_base64 "$CLUSTER_NAME")
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

unset XMPP_JID XMPP_PASSWORD ALERTS_ROOM_PASSWORD PRINTER_ROOM_PASSWORD XIYOHE_ROOM_PASSWORD
unset MQTT_ANONYMOUS MQTT_USERNAME MQTT_PASSWORD MQTT_BROKER CLUSTER_NAME

echo ""
echo "✓ SealedSecret created: ${OUTPUT_FILE}"
echo "✓ kustomization updated: ${KUSTOMIZATION_FILE}"
echo ""
echo "Next steps:"
echo "1. Sprawdź plik ${OUTPUT_FILE}"
echo "2. Commit: ${OUTPUT_FILE} i ${KUSTOMIZATION_FILE}"
echo "3. Push i manualny sync ArgoCD: argocd app sync mqtt-xmpp-bridge"

#!/bin/bash

set -euo pipefail

# Creates the SealedSecret "mailarchive-imap" for apps/mailarchive.
#
# It holds two unrelated sets of credentials:
#
#   gmail, o2       the UPSTREAM passwords mbsync uses to log in to the mail
#                   providers and pull mail down. For gmail this must be an
#                   application password, not the account password.
#   dovecot-users   the LOCAL passwords, in Dovecot passwd-file format, that the
#                   mail client (Thunderbird / K-9) uses to read the archive
#                   over IMAPS. Stored as SHA-512 crypt hashes, never plaintext.
#
# Nothing is echoed and no plaintext ever reaches disk: the Secret is piped
# straight into kubeseal and only the encrypted result is written out.

APP_DIR="apps/mailarchive"
KUSTOMIZATION_FILE="${APP_DIR}/kustomization.yaml"
OUTPUT_FILE="${APP_DIR}/sealed-secret.yaml"
NAMESPACE="mailarchive"
SECRET_NAME="mailarchive-imap"
CONTROLLER_NAME="${SEALED_SECRETS_CONTROLLER_NAME:-sealed-secrets-controller}"
CONTROLLER_NAMESPACE="${SEALED_SECRETS_CONTROLLER_NAMESPACE:-kube-system}"
KUBECTL_CONTEXT="${KUBECTL_CONTEXT:-}"

# Must match the User lines in apps/mailarchive/mbsync-configmap.yaml and the
# Maildir paths its Inbox directives point at.
GMAIL_LOGIN="lkrzyzak@gmail.com"
O2_LOGIN="dragu645@o2.pl"

for bin in kubectl kubeseal openssl; do
    if ! command -v "$bin" &> /dev/null; then
        echo "Error: $bin is not installed." >&2
        [[ "$bin" == "kubeseal" ]] && echo "Install: https://github.com/bitnami-labs/sealed-secrets" >&2
        exit 1
    fi
done

if [[ ! -f "$KUSTOMIZATION_FILE" ]]; then
    echo "Error: Missing file: $KUSTOMIZATION_FILE" >&2
    echo "Run this from the repository root." >&2
    exit 1
fi

read_password() {
    local label="$1"
    local value="" confirm=""

    while true; do
        read -r -s -p "${label}: " value >&2
        echo >&2
        if [[ -z "$value" ]]; then
            echo "  puste hasło, spróbuj ponownie" >&2
            continue
        fi
        read -r -s -p "${label} (powtórz): " confirm >&2
        echo >&2
        if [[ "$value" != "$confirm" ]]; then
            echo "  hasła się różnią, spróbuj ponownie" >&2
            continue
        fi
        break
    done
    printf '%s' "$value"
}

echo "mailarchive SealedSecret generator"
echo "================================="
echo ""
echo "Namespace:   ${NAMESPACE}"
echo "Secret:      ${SECRET_NAME}"
echo "Output:      ${OUTPUT_FILE}"
echo "Controller:  ${CONTROLLER_NAME} (ns: ${CONTROLLER_NAMESPACE})"
if [[ -n "$KUBECTL_CONTEXT" ]]; then
    echo "kubectl ctx: ${KUBECTL_CONTEXT}"
fi
echo ""
echo "1/2 — hasła DO POBIERANIA poczty (używa ich mbsync, wychodzące IMAPS):"
echo "      gmail wymaga hasła aplikacji: https://myaccount.google.com/apppasswords"
echo ""

GMAIL_PASS="$(read_password "  hasło aplikacji gmail (${GMAIL_LOGIN})")"
O2_PASS="$(read_password "  hasło o2 (${O2_LOGIN})")"

echo ""
echo "2/2 — hasła DO CZYTANIA archiwum (wpiszesz je w Thunderbirdzie/K-9)."
echo "      Konta lokalne nazywają się 'gmail' i 'o2'. Mogą, ale nie muszą,"
echo "      różnić się od powyższych; zapisane będą jako hasze SHA-512."
echo ""

DOVECOT_GMAIL_PASS="$(read_password "  hasło lokalne dla konta 'gmail'")"
DOVECOT_O2_PASS="$(read_password "  hasło lokalne dla konta 'o2'")"

echo ""
read -r -p "Wygenerować ${OUTPUT_FILE}? [y/N]: " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

KUBECTL_ARGS=()
if [[ -n "$KUBECTL_CONTEXT" ]]; then
    KUBECTL_ARGS+=(--context "$KUBECTL_CONTEXT")
fi

# openssl passwd -6 produces a SHA-512 crypt hash, which is what Dovecot's
# default password scheme (CRYPT) expects. The {CRYPT} prefix is written out
# explicitly so the scheme cannot be misread if the default ever changes.
DOVECOT_USERS="$(printf 'gmail:{CRYPT}%s\no2:{CRYPT}%s\n' \
    "$(openssl passwd -6 "$DOVECOT_GMAIL_PASS")" \
    "$(openssl passwd -6 "$DOVECOT_O2_PASS")")"

TMP_OUTPUT="$(mktemp)"
trap 'rm -f "$TMP_OUTPUT"' EXIT

# --from-file=/dev/stdin is avoided; --from-literal keeps the values out of the
# filesystem entirely. The Secret manifest exists only in this pipe.
if ! kubectl "${KUBECTL_ARGS[@]}" create secret generic "$SECRET_NAME" \
        --namespace "$NAMESPACE" \
        --from-literal=gmail="$GMAIL_PASS" \
        --from-literal=o2="$O2_PASS" \
        --from-literal=dovecot-users="$DOVECOT_USERS" \
        --dry-run=client -o json \
    | kubeseal \
        --format yaml \
        --controller-name "$CONTROLLER_NAME" \
        --controller-namespace "$CONTROLLER_NAMESPACE" \
    > "$TMP_OUTPUT"; then
    echo "" >&2
    echo "Error: kubeseal failed. Typowe przyczyny:" >&2
    echo "  - brak dostępu do kontrolera ${CONTROLLER_NAME} w ns ${CONTROLLER_NAMESPACE}" >&2
    echo "  - zły kontekst kubectl (ustaw KUBECTL_CONTEXT=...)" >&2
    exit 1
fi

if [[ ! -s "$TMP_OUTPUT" ]]; then
    echo "Error: kubeseal produced an empty file; refusing to overwrite ${OUTPUT_FILE}." >&2
    exit 1
fi

mv "$TMP_OUTPUT" "$OUTPUT_FILE"

if ! grep -q "sealed-secret.yaml" "$KUSTOMIZATION_FILE"; then
    printf '  - sealed-secret.yaml\n' >> "$KUSTOMIZATION_FILE"
    echo "✓ kustomization updated: ${KUSTOMIZATION_FILE}"
fi

unset GMAIL_PASS O2_PASS DOVECOT_GMAIL_PASS DOVECOT_O2_PASS DOVECOT_USERS

echo ""
echo "✓ SealedSecret created: ${OUTPUT_FILE} (${SECRET_NAME})"
echo ""
echo "Dalej:"
echo "1. Sprawdź, że w ${OUTPUT_FILE} nie ma nic jawnego:"
echo "     grep -c encryptedData ${OUTPUT_FILE}"
echo "2. git add ${OUTPUT_FILE} ${KUSTOMIZATION_FILE} && git commit"
echo "3. git push origin master        # ArgoCD czyta z origin, nie z gitei"
echo "4. Hard refresh + sync:"
echo "     kubectl -n argocd annotate applications.argoproj.io kustomize-mailarchive \\"
echo "         argocd.argoproj.io/refresh=hard --overwrite"
echo "     kubectl -n argocd patch applications.argoproj.io kustomize-mailarchive \\"
echo "         --type merge -p '{\"operation\":{\"sync\":{\"prune\":false}}}'"
echo "5. Restart Dovecota, żeby wczytał plik haseł:"
echo "     kubectl -n ${NAMESPACE} rollout restart deployment/dovecot"
echo "6. Pierwszy sync ręcznie (patrz ${APP_DIR}/README.md):"
echo "     kubectl -n ${NAMESPACE} create job --from=cronjob/mbsync mbsync-manual-1"

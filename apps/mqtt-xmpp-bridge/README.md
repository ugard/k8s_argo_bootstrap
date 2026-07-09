# mqtt-xmpp-bridge

Manifesty wdrażają `xmpp-omemo-core` jako most MQTT ↔ XMPP w namespace `xmpp-bridge`.

## Wariant zalecany: SealedSecret generowany runtime

Do wygenerowania zaszyfrowanego sekretu użyj skryptu:

```bash
./scripts/create-mqtt-xmpp-bridge-sealed-secret.sh
```

Skrypt:
- pyta interaktywnie o wszystkie credentiale,
- pozwala wybrać tryb MQTT anonymous (wtedy `MQTT_USERNAME` i `MQTT_PASSWORD` są ustawiane na puste wartości),
- nie zapisuje jawnego `Secret` do plików,
- generuje tylko `apps/mqtt-xmpp-bridge/sealed_secret.yaml`,
- automatycznie dopisuje `sealed_secret.yaml` do `apps/mqtt-xmpp-bridge/kustomization.yaml` (jeśli wpisu jeszcze nie ma).

> Uwaga: dopóki nie uruchomisz skryptu, `kustomization.yaml` nie zawiera jeszcze `sealed_secret.yaml`.

Wymagania:
- `kubectl`
- `kubeseal`
- dostęp do klastra z działającym Sealed Secrets Controller

Opcjonalnie możesz wskazać context:

```bash
KUBECTL_CONTEXT=ai-agent ./scripts/create-mqtt-xmpp-bridge-sealed-secret.sh
```

Dla niestandardowej nazwy/namespace kontrolera:

```bash
SEALED_SECRETS_CONTROLLER_NAME=sealed-secrets-controller \
SEALED_SECRETS_CONTROLLER_NAMESPACE=kube-system \
./scripts/create-mqtt-xmpp-bridge-sealed-secret.sh
```

## Wymagane klucze w sekrecie `xmpp-credentials`

- `XMPP_JID`
- `XMPP_PASSWORD`
- `ALERTS_ROOM_PASSWORD`
- `PRINTER_ROOM_PASSWORD`
- `XIYOHE_ROOM_PASSWORD`
- `MQTT_USERNAME` (może być puste przy MQTT anonymous)
- `MQTT_PASSWORD` (może być puste przy MQTT anonymous)
- `MQTT_BROKER`
- `CLUSTER_NAME`

## Walidacja lokalna

```bash
kubectl kustomize apps/mqtt-xmpp-bridge
```

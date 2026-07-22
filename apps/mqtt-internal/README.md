# mqtt-internal — wewnętrzny broker MQTT

Druga, wewnętrzna instancja Mosquitto — wyłącznie dla ruchu wewnątrz klastra
(alerty → mostek XMPP, drukarka 3D). Broker Zigbee w ns `hass`
(`mosquitto-mqtt.hass.svc`, anonimowy, LoadBalancer) pozostaje nietknięty.

## Różnice względem brokera w `hass`

- `ClusterIP` — niedostępny spoza klastra
- `allow_anonymous false` — logowanie hasłem (plik `passwd` generowany
  przy starcie przez initContainer z sekretu `mosquitto-credentials`)
- ACL per użytkownik (`configmap.yaml`): `alert-webhook` może tylko
  publikować `alerts/#`, `xmpp-bridge` subskrybuje trasy mostka
- persystencja na PVC (sesje trwałe mostka, QoS 1)

## Adres

`tcp://mosquitto.mqtt-internal.svc:1883`

## Sekrety

`scripts/create-mqtt-internal-sealed-secret.sh` generuje
`sealed_secret.yaml` (hasła użytkowników `xmpp-bridge` i `alert-webhook`).
Te same hasła muszą trafić do klientów:

- `xmpp-bridge` → secret `xmpp-credentials` w ns `xmpp-bridge`
  (`scripts/create-mqtt-xmpp-bridge-sealed-secret.sh`,
  `MQTT_BROKER=tcp://mosquitto.mqtt-internal.svc:1883`)
- `alert-webhook` → konfiguracja alert-webhook w ns `monitoring`

## ACL a trasy mostka

Plik `acl` w `configmap.yaml` musi być spójny z
`apps/mqtt-xmpp-bridge/configmap-routes.yaml` — dodając trasę w mostku,
dodaj odpowiedni wpis `topic read/write` dla użytkownika `xmpp-bridge`.

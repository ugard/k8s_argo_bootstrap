# Deployments Index — k8s_argo_bootstrap

> Auto-generated reference for AI agents. Summarizes every ArgoCD `Application`
> managed by this repo (the "App of Apps" root Helm chart). Last updated: 2026-06-21.

## Repository layout

```
Chart.yaml                  # root Helm chart "applications" v0.1.0
values.yaml                 # global defaults: repoURL, targetRevision, destination.server
templates/                  # ArgoCD Application CRs (one per app, helm-* or kustomize-*)
apps/<name>/                # per-app kustomize overlays + manifests + sealed secrets
manifests/prometheus-rules/ # PrometheusRule CRs consumed by the prometheus App
scripts/                    # one-off bootstrap/helper scripts (secrets, cloudflared, postgres users)
doc/                        # documentation (backup flows, this index)
edit-sealed-secret.sh       # edit an existing live secret -> re-seal -> commit
view-secret-key.sh          # view a decrypted key from a live secret
SEALED_SECRET_MANAGEMENT.md # workflow for sealed secrets
```

- **Global values** (`values.yaml`):
  - `spec.destination.server`: `https://kubernetes.default.svc`
  - `spec.source.repoURL`: `https://github.com/ugard/k8s_argo_bootstrap`
  - `spec.source.targetRevision`: `HEAD`
- All `Application` CRs are created in namespace `argocd`, project `default`.
- Some apps use ArgoCD **multi-source** (`sources:`): a Helm chart + a git path for
  kustomize overlays + a `ref: values` source to load `valueFiles: - $values/...`.
- Sync option `ServerSideApply=true` is commonly set; `CreateNamespace=true` only on a few
  (metallb, openebs-helm).

## Storage classes in use (PVCs)
- `rook-ceph-block` — default Ceph RBD block (size 3 replicated)
- `rook-ceph-filesystem` — CephFS
- `openebs-zfspv` — OpenEBS ZFS-LocalPV (most stateful workloads)
- `openebs-zfspv-affinity` — variant with affinity

## Domains (hosts exposed via ingress, zone `ugard.win`)
appflowy admin/web, bookshelf, bytestash, drone, flashweb, garage, gitea, gotify,
grafana, hass, hc (healthchecks), hoarder, home (gethomepage), immich, jellyfin,
kiosk (immich-kiosk), lychee, manyfold, minio, nodered, notes (obsidian),
openarchiver, otgw, paperless, pico (picoshare), prowlarr, radarr, rtorrent,
sonarr, spoolman, syncthing, vault (vaultwarden). Also `prom.ugard.win`,
`monitoring.ugard.win`, `registry.ugard.win`, `vikunja.ugard.win` (from helm-* apps).

## TLS / certificates
- `cert-manager` (jetstack) installed in namespace `cert-manager2`, with a
  Cloudflare-based `letsencrypt-cloudflare` ClusterIssuer and a **dynu** DNS01 webhook
  (`cert-manager-webhook-dynu`, `apps/cert-manager/dynu-webhook`).
- Most public ingresses annotate `cert-manager.io/cluster-issuer: letsencrypt-cloudflare`
  and use ingressClassName `kustomize-traefik`.

## Networking / ingress
- **Traefik** (`kustomize-traefik`, namespace `traefik`) — chart v37.1.2, LB IP
  `192.168.10.253`, exposed via Tailscale annotation.
- **MetalLB** (`metallb`, namespace `metallb-system`) — chart 0.15.3, FRR speaker;
  L2Advertisement + IPAddressPool in `apps/metallb`.
- **Cloudflared** (`cloudflared`, namespace `cloudflared`) — community chart 2.2.4,
  tunnel config + cert as sealed secrets.
- **Tailscale operator** (`kustomize-tailscale-operator`, namespace `tailscale`) —
  chart 1.92.5.

## Cluster infra / storage
| App (template) | Namespace | Type | Chart / notes |
|---|---|---|---|
| rook-ceph (`helm-rook-ceph`) | rook-ceph2 | helm | rook-ceph + rook-ceph-cluster v1.19.4; Ceph on 3 nodes (OSDs on specific disk by-id), block/fs/object stores, serviceMonitor + PrometheusRules |
| openebs-helm (`helm-openebs.yaml`) | kube-system | helm | openebs 4.4.0; local hostpath + ZFS-LocalPV enabled, lvm/mayastor/disabled; serviceMonitor on |
| openebs (kustomize) (`kustomize-openebs`) | openebs | kustomize | `apps/openebs`: storage-classes, openebs-vsc (VolumeSnapshotClass) |
| metallb (`helm-metallb`) | metallb-system | helm+kustomize | chart 0.15.3 + `apps/metallb` pools/ads |
| trivy (`helm-trivy`) | trivy-system | helm | trivy-operator 0.30.0 (security scanning) |

## Cert-manager
- `helm-cert-manager` (namespace `cert-manager2`): jetstack cert-manager v1.16.1,
  installCRDs, prometheus servicemonitor, DNS01 recursive nameservers 1.1.1.1/8.8.8.8.
- `helm-cert-manager-webhook` (`cert-manager-webhook-dynu`): dynu DNS01 webhook from
  `apps/cert-manager/dynu-webhook`.
- `apps/cert-manager`: cloudflare-secret, sealed-secret, cluster-issuers.

## Monitoring / observability
| App (template) | Namespace | Type | Notes |
|---|---|---|---|
| prometheus (`helm-prometheus-operator`) | monitoring | helm+kustomize | kube-prometheus-stack 75.15.1; grafana enabled; ingresses prom.ugard.win & monitoring.ugard.win; Prometheus storage rook-ceph-block 10Gi; alertmanager -> ntfy via alert-webhook; loads `manifests/prometheus-rules` (zfs, backup, openebs, cert-manager) |
| monitoring-secrets (`kustomize-monitoring-secrets`) | monitoring | kustomize | `apps/monitoring`: ntfy sealed secret, zfs-exporter, grafana disk dashboard |
| grafana (`kustomize-grafana`) | grafana | kustomize | `apps/grafana`: standalone grafana + datasources + dashboards |
| alert-webhook (`kustomize-alert-webhook`) | monitoring | kustomize | custom Flask-ish webhook (`apps/alert-webhook`: Dockerfile, webhook.sh), image `registry.ugard.win/alert-webhook:<sha>`, kaniko build job; relays Alertmanager -> ntfy |

## Backup
| App (template) | Namespace | Type | Notes |
|---|---|---|---|
| velero (`helm-velero`) | velero | helm | velero 10.0.10; nodeAgent + CSI; BSLs: `garage` (S3 @ http://192.168.10.5:3900) default, `scaleway` (pl-waw); VSL csi default |
| velero-healthchecks (`kustomize-velero-healthchecks`) | velero | kustomize | `apps/velero`: schedules, resource-modifiers, change-storage-class config, healthcheck cronjob + python script |
| benji (`kustomize-benji`) | backup-system | kustomize | `apps/benji-backup`: zrepl push/sink for Garage ZFS replication + zrepl healthcheck; image `registry.ugard.win/zrepl:latest` |
| (postgres backup) | postgres | via velero schedule | `postgres-backup` schedule 04:00, pg_dumpall pre-hook, FS backup to Garage (see `doc/backup/README.md`) |

See `doc/backup/README.md` for full backup topology (Velero/Benji/Zrepl/Postgres).

## CI/CD
| App (template) | Namespace | Type | Notes |
|---|---|---|---|
| drone (`helm-drone`) | drone | helm+kustomize | drone 0.6.5 + drone-runner-kube 0.1.10; values from git `apps/drone`; overlays `apps/drone` & `apps/drone-runner` |
| gitea (`kustomize-gitea`) | gitea | kustomize | `apps/gitea`: gitea deployment/ingress/PVC/migrate, sealed secret (app.ini), gitea image gitea/gitea:latest |
| zot-registry (`helm-zot-registry`) | registry | helm | zot 0.1.104; ingress registry.ugard.win; PVC rook-ceph-block 8Gi; metrics on (internal image registry) |

## Databases / caches
| App (template) | Namespace | Type | Notes |
|---|---|---|---|
| postgres (`kustomize-postgres`) | postgres | kustomize | `apps/postgres`: postgres:16 + pgvector variant used by some apps; PVC + sealed secret; backed up by velero schedule |
| openarchiver (`kustomize-openarchiver`) | openarchiver | kustomize | multi-component: meilisearch v1.15, valkey 8, tika, openarchiver app; ingress openarchiver.ugard.win |
| hoarder (`kustomize-hoarder`) | hoarder | kustomize | karakeep 0.30.0 + meilisearch v1.11.1 + chrome (headless); sealed secret; `ENV_UPDATE.md` doc |
| postgres-of-openarchiver | openarchiver | script | `scripts/create-openarchiver-postgres-user.sh`, `generate-openarchiver-secrets.sh` |

## Home automation / IoT
| App (template) | Namespace | Type | Notes |
|---|---|---|---|
| hass (`kustomize-hass`) | hass | kustomize+helm | home-assistant 2026.2.1 (ghcr) + zigbee2mqtt chart 2.6.3 (ember adapter, tcp://192.168.100.122:6638), mosquitto, otgw-ds/otgw-test, zigbee-converter configmap; hosts hass.ugard.win & otgw.ugard.win |
| mqtt-internal (`kustomize-mqtt-internal`) | mqtt-internal | kustomize | wewnętrzny Mosquitto 2 (ClusterIP `mosquitto.mqtt-internal.svc:1883`, allow_anonymous false, passwd z sekretu `mosquitto-credentials` via initContainer, ACL per klient, PVC 1Gi); dla alertów i mostka XMPP — broker zigbee w `hass` bez zmian |
| mqtt-xmpp-bridge (`kustomize-mqtt-xmpp-bridge`) | xmpp-bridge | kustomize | xmpp-omemo-core (MQTT→XMPP/OMEMO bridge, image `registry.ugard.win/xmpp-omemo-core`); trasy w `configmap-routes.yaml` (alerts/# → k8s-alerts@conference.xmpp.jp, printer/*); secret `xmpp-credentials` (sealed), PVC omemo-store, replicas 1 + Recreate |
| immich-kiosk (`kustomize-immich-kiosk`) | immich-kiosk | kustomize | `apps/immich-kiosk/argo-app`; ghcr.io/damongolding/immich-kiosk (host kiosk.ugard.win) |
| spoolman (`kustomize-spoolman`) | spoolman | kustomize | spoolman (3D filament) |
| zmod-telegram (`kustomize-zmod-telegram`) | zmod-telegram | kustomize | moonraker-telegram-bot for 3D printer |
| flashforge/flashweb (`kustomize-flashforge`) | flashweb | kustomize | custom flashforge printer web; image `registry.ugard.win/flashweb:1` |

## Media / downloads
| App (template) | Namespace | Type | Notes |
|---|---|---|---|
| jellyfin (`kustomize-jellyfin`) | jellyfin | helm+kustomize | jellyfin chart 2.3.0, rclone media PVC + bridge-service, rclone sealed secret, gluetun vpn |
| immich (`kustomize-immich`) | immich | helm+kustomize | immich chart 0.10.3 + postgres + PVC + sealed secret (host immich.ugard.win) |
| lychee (`kustomize-lychee`) | lychee | kustomize | lycheeorg/lychee, ingress/PVC/sealed secret |
| rtorrent (`kustomize-rtorrent`) | rtorrent | kustomize | transmission + radarr + sonarr + prowlarr (linuxserver/hotio); postgres for sonarr; sftpgo; migrate jobs; hosts rtorrent/radarr/sonarr/prowlarr.ugard.win |
| manyfold (`kustomize-manyfold`) | manyfold | kustomize | manyfold 0.132.0 (3D model library) + sealed secret |
| bookshelf (`kustomize-bookshelf`) | bookshelf | kustomize | ghcr.io/pennydreadful/bookshelf:hardcover + PVC |

## Productivity / self-hosted apps
| App (template) | Namespace | Type | Notes |
|---|---|---|---|
| appflowy (`kustomize-appflowy` no — `kustomize-*`? actual: appflowy) | appflowy | kustomize | full AppFlowy stack: cloud, web, ai, gotrue, admin; admin/web_hosts; sealed secret |
| firefly-iii (`helm-firefly-iii`) | firefly | helm+kustomize | firefly-iii chart 1.8.2 + importer 1.4.0; values from `apps/firefly`; sealed secret |
| vikunja (`helm-vikunja`) | vikunja | helm+git | oci://ghcr.io/go-vikunja helm 1.0.0 + `apps/vikunja` overlay; ingress vikunja.ugard.win; postgres disabled (external) |
| paperless (`kustomize-paperless`) | paperless | kustomize | paperless-ngx + tika + gotenberg + sftpgo + postgres sealed secret; network; migrate; host paperless.ugard.win |
| obsidian (`kustomize-obsidian`) | obsidian | kustomize | linuxserver/obsidian; gitea pull secrets; para-init configmap+job; host notes.ugard.win |
| vaultwarden (`kustomize-vaultwarden`) | vaultwarden | kustomize | vaultwarden server + ingress/PVC/migrate; host vault.ugard.win |
| healthchecks (`kustomize-healthchecks`) | healthchecks | kustomize | healthchecks.io self-host; ingress hc.ugard.win |
| hoarder | (see databases) | | |
| picoshare (`kustomize-picoshare`) | picoshare | kustomize | mtlynch/picoshare; host pico.ugard.win |
| bytestash (`kustomize-bytestash`) | bytestash | kustomize | ghcr.io/jordan-dalby/bytestash; host bytestash.ugard.win |
| gethomepage (`kustomize-gethomepage`) | gethomepage | kustomize | homepage v1.9.0 dashboard; host home.ugard.win |
| gotify (`kustomize-gotify`) | gotify | kustomize | gotify server; host gotify.ugard.win |
| adguard (`kustomize-adguard`) | adguard | kustomize | adguardhome |
| node-red (`kustomize-nodered`) | node-red | helm+git | schwarzit node-red chart 0.33.1; values from `apps/node-red`; host nodered.ugard.win |
| minio (`kustomize-minio`) | minio | kustomize | minio dev + PVC; host minio.ugard.win |
| syncthing (`kustomize-syncthing`) | syncthing | kustomize | syncthing + PVC; host syncthing.ugard.win |
| garage (`kustomize-garage`) | garage | kustomize | dxflrs/garage v2.2.0 (S3-compatible); sealed secret; backed up by Velero+Zrepl; host garage.ugard.win |
| ai-agent-readonly (`kustomize-ai-agent-readonly`) | ai-agent | kustomize | namespace + RBAC only (read-only service account for AI agents) |

## Internal container registry
- `registry.ugard.win` (zot) hosts custom images referenced by digest/sha:
  `alert-webhook:<sha>`, `flashweb:1`, `zrepl:latest`, `zfs-exporter:latest`.

## Scripts (`scripts/`)
- `create-cloudflared-sealed-secret.sh`, `create-cloudflare-secret.sh` — cloudflare tunnel secrets
- `create-openarchiver-postgres-user.sh`, `generate-openarchiver-secrets.sh` — openarchiver DB/secrets
- `setup-sonarr-postgres.sh` — sonarr postgres bootstrap

## Convention quick-reference (for agents editing this repo)
- Per-app dir `apps/<name>/` with `kustomization.yaml`; resources: `namespace.yaml`,
  `*.yaml` (deployment/service/pvc/ingress/sealed_secret), optionally `migrate.yaml` /
  `*-init-job.yaml`.
- Register new app by adding `templates/kustomize-<name>.yaml` (copy an existing
  kustomize template) or `templates/helm-<name>.yaml` for a helm+overlay combo.
- `metadata.name` in template need not equal the namespace; e.g. `kustomize-gitea` ->
  namespace `gitea`.
- For helm+overlay apps the pattern is multi-source: chart + git `ref: values` +
  git `path: apps/<name>`; values loaded via `$values/apps/<name>/values.yaml`.
- **Secrets**: never commit plain `Secret`; always `SealedSecret` (filename usually
  `sealed_secret.yaml` / `*.sealed-secret.yaml`). To modify use
  `./edit-sealed-secret.sh <ns> <secret> [key]`. See `SEALED_SECRET_MANAGEMENT.md`.
- Indentation 2 spaces; kebab-case filenames.
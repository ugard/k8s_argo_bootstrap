# mailarchive — mbsync + Dovecot 2.4 + flatcurve

A boring, durable mail archive. `mbsync` pulls IMAP down into a Maildir on a
CephFS volume; Dovecot serves that Maildir over IMAPS on the LAN with
full-text search. There is no web application and no database — all state is
plain files sitting next to the mail, so losing a pod costs nothing.

This replaces what `apps/openarchiver` was supposed to do. **OpenArchiver was
scaled to zero on 2026-07-30** — its Deployments are stopped but its PVCs,
secret and Ingress remain, so it can be brought back. Deleting it is still a
separate decision.

## Shape

| component | what it is |
|---|---|
| `mailarchive-data` PVC | 60Gi, `rook-ceph-filesystem`, **RWX**, labelled `backup-this-pvc: "true"` |
| `mbsync` CronJob | hourly, `registry.ugard.win/mbox_sync`, one-way pull into the Maildir |
| `dovecot` Deployment | `dovecot/dovecot:2.4.4`, 1 replica, `Recreate` |
| `dovecot` Service | LoadBalancer on **192.168.10.220**, port **993** |
| `mailarchive-tls` Certificate | `mail-archive.ugard.win` via `letsencrypt-cloudflare` (DNS-01) |
| `mailarchive-imap` SealedSecret | upstream IMAP passwords + local login hashes |

The PVC **must** be RWX: the CronJob writes the Maildir while the Deployment
reads and indexes it. On a ReadWriteOnce class the second consumer hangs in
Multi-Attach forever. Maildir is designed for lockless concurrent access, so
sharing is safe.

Both containers run as uid/gid **1000** (`vmail` in the Dovecot image). This is
not cosmetic: mbsync creates the folder directories and Dovecot has to write
its index and Xapian files *inside* them.

## Storage layout

```
/srv/vmail/                      <- the PVC
  gmail/mail/                    <- Maildir root = INBOX (cur/ new/ tmp/)
    .mbsyncstate                 <- mbsync sync state, survives pod restarts
    .uidvalidity
    .work/                       <- a subfolder
    .budowa.materiały/           <- nested folder, "/" flattened to "."
    .[Gmail].Wysłane/
      fts-flatcurve/             <- Xapian index, created on demand
  o2/mail/
```

`mail_home = /srv/vmail/%{user | lower}` and `mail_path = ~/mail` both come from
the image and are already correct. Folder names are stored as literal UTF-8
(`.dachówka`), not modified UTF-7, which matches the image's
`mailbox_list_utf8 = yes`.

## The two settings that make this work

Neither is obvious, and both fail *silently*:

1. **`mailbox_list_layout = maildir++`** (in `dovecot-configmap.yaml`). The image
   ships `mailbox_list_layout = index`, which cannot see mbsync's `.Folder`
   directories at all — with the stock value the archive appears to contain
   nothing but an empty INBOX. Maildir++ is the one layout mbsync and Dovecot
   agree on.

2. **The Dovecot config is mounted as individual files via `subPath`**, never as
   a directory over `/etc/dovecot/conf.d`. A directory mount hides the files the
   image ships there — including `fts.conf`, which *is* the entire flatcurve
   configuration. Mount the directory and full-text search quietly disappears.
   `dovecot.conf` ends with `!include_try conf.d/*.conf` and is processed
   alphabetically, so the `zz-` prefix makes the overrides win.

## Why the mbsync settings are what they are

`mbsync-configmap.yaml` sets all four of these globally **and** again in every
Channel. Three are already the upstream default; they are written out anyway
because a default is invisible, and an invisible default is not an adequate
guard on a private mailbox.

```
Sync Pull New    only newly appeared messages, only server -> archive.
                 No flags, no deletions, nothing ever uploaded.
Create Near      create missing folders locally only; never on the provider.
Remove None      never propagate folder deletions in either direction.
Expunge None     never permanently delete a message on either side.
```

Consequence, and the whole point: **deleting mail or a whole label on the
provider does not touch the archived copy, and nothing the archive does is ever
pushed back up.** This was verified by expunging a message and deleting a folder
on a test server and confirming both local copies survived.

Two more non-obvious details:

- `Inbox` must have **no trailing slash**. With one, mbsync builds `mail//` and
  dies with `cannot create mailbox: File exists`.
- In `SubFolders Maildir++` mode mbsync **rejects** `Path`, so `Inbox` is the only
  location directive.
- `INBOX` is listed explicitly in `Patterns` because mbsync does not match INBOX
  with wildcards. With `"*"` alone the inbox is silently skipped.

### Which folders are archived

gmail uses `"![Gmail]/*"` followed by re-including the two wanted folders. This
is on purpose: Gmail's special folders are localised, so blacklisting
`[Gmail]/Spam` by name would silently do nothing if the name differs by one
character. Excluding the namespace and adding back what is wanted fails closed.

Dropped for gmail: All Mail (holds a copy of *every* message, which would double
the archive), Spam, Trash, and the Important/Starred virtual views. Kept: INBOX,
every user label, Sent, Drafts.

**o2's folder names have not been enumerated yet** — the exclusion list carries
both English and Polish spellings as a guess. Confirm the real list:

```bash
kubectl -n mailarchive create job --from=cronjob/mbsync mbsync-list
# then, before it finishes, or from the pod logs:
kubectl -n mailarchive logs job/mbsync-list
```

To list folders without syncing anything, run mbsync by hand in a throwaway pod
(read-only, connects but writes nothing):

```bash
kubectl -n mailarchive run mbsync-list --rm -it --restart=Never \
    --image=registry.ugard.win/mbox_sync:217f6708 --overrides='
{"spec":{"securityContext":{"runAsUser":1000,"runAsGroup":1000,"fsGroup":1000},
 "containers":[{"name":"m","image":"registry.ugard.win/mbox_sync:217f6708",
  "args":["-c","/config/mbsyncrc","--list","o2"],
  "volumeMounts":[{"name":"c","mountPath":"/config"},{"name":"s","mountPath":"/secrets"}]}],
 "volumes":[{"name":"c","configMap":{"name":"mbsync-config"}},
            {"name":"s","secret":{"secretName":"mailarchive-imap","defaultMode":288}}]}}'
```

## Operations

### First-time setup (secret is NOT in git)

The SealedSecret must be generated by you — it contains passwords, and no
`Secret` resource is ever committed to this repo.

```bash
cd /home/luck/work/k8s/k8s_argo_bootstrap
./scripts/create-mailarchive-sealed-secret.sh
```

It asks for four values: the gmail **app** password and the o2 password (used by
mbsync to pull), plus the two local passwords you will type into your mail
client. The local ones are stored as SHA-512 crypt hashes.

**Until that script has been run and committed, the CronJob will fail on the
missing secret and Dovecot will not start. That is expected, not a fault.**

### Force a sync now

```bash
kubectl -n mailarchive create job --from=cronjob/mbsync mbsync-manual-1
kubectl -n mailarchive logs -f job/mbsync-manual-1
```

The first run downloads everything and will take hours for a ~110k-message
mailbox. `concurrencyPolicy: Forbid` means the hourly schedule will skip while it
is still going, so a long first run is safe.

Watch it grow:

```bash
kubectl -n mailarchive exec deploy/dovecot -- sh -c \
  'du -sh /srv/vmail/gmail /srv/vmail/o2' 2>/dev/null
```

### Add another account

1. Add `IMAPAccount` / `IMAPStore` / `MaildirStore` / `Channel` blocks to
   `mbsync-configmap.yaml`, copying an existing pair. Point `Inbox` at
   `/srv/vmail/<name>/mail`. Repeat all four safety settings.
2. Add the upstream password and a local login line to the secret by re-running
   `./scripts/create-mailarchive-sealed-secret.sh` (it rewrites the whole
   secret, so have all passwords to hand), or use
   `./edit-sealed-secret.sh mailarchive mailarchive-imap` to edit in place.
3. Commit, push to `origin master`, sync, then
   `kubectl -n mailarchive rollout restart deployment/dovecot`.

`mbsync -a` picks up new Channels with no further wiring.

### Change passwords

Never edit the encrypted blob by hand.

```bash
./edit-sealed-secret.sh mailarchive mailarchive-imap dovecot-users
# or regenerate everything:
./scripts/create-mailarchive-sealed-secret.sh
```

A changed `dovecot-users` needs a restart to be read:
`kubectl -n mailarchive rollout restart deployment/dovecot`.

Local password hashes are SHA-512 crypt; generate one with
`openssl passwd -6` and write the line as `user:{CRYPT}$6$...`.

### Rebuild the full-text index

flatcurve indexes on demand (`fts_autoindex = yes`), so this is only needed if an
index is corrupt or a search misses mail you know is there.

```bash
# one mailbox
kubectl -n mailarchive exec deploy/dovecot -- \
    /dovecot/bin/doveadm fts rescan -u gmail
# force a full reindex of everything for one account
kubectl -n mailarchive exec deploy/dovecot -- \
    /dovecot/bin/doveadm index -u gmail '*'
```

The Xapian index lives in `fts-flatcurve/` inside each folder directory. It is
rebuildable, so losing it is never a data loss.

### Mail client

Host `mail-archive.ugard.win` (or `192.168.10.220`), port **993**, SSL/TLS,
normal password. Username is `gmail` or `o2` — the local account name, not the
email address. The certificate is a real Let's Encrypt one, so no exception is
needed, but the hostname must resolve to `192.168.10.220` from where you are.

## Known behaviours, not bugs

- **A folder deleted upstream makes the Job exit non-zero, every hour, forever.**
  You will see `Error: channel <name>: far side box <folder> cannot be opened
  anymore.` This is `Remove None` doing its job — the archived copy is being
  kept, and mbsync refuses to quietly forget a folder it has state for. Other
  folders still sync normally in the same run; only the exit code is affected.
  To silence it, either add `"!<folder>"` to that Channel's `Patterns`, or drop
  the stale state with
  `rm /srv/vmail/<account>/mail/.<folder>/.mbsyncstate`.
- **Gmail labels mean one message is stored several times**, once per label it
  carries. That is inherent to mapping labels onto folders and is why All Mail is
  excluded.
- The CronJob image is built by Drone from
  [mbox_sync](https://gitea.ugard.win/lkrzyzak/mbox_sync) and pinned to a commit
  SHA. It is `alpine:3.23` plus `isync` from the signed Alpine repository, so
  the supply chain is unchanged from the earlier runtime `apk add` — but the
  package is resolved at build time, which keeps an Alpine mirror off the
  critical path of every hourly run and lets the container run as uid 1000 from
  the start instead of beginning as root and dropping privileges with `su-exec`.
  To pick up a new isync, push to that repo and re-pin the tag here.
- Do **not** set a `USER_PASSWORD` env var on the Dovecot Deployment. The
  image's stock `auth.conf` uses it for a catch-all `passdb static` that would
  let anyone log in as any user. This app replaces that file precisely so the
  variable has no effect, but do not reintroduce it.
- Ports 31143 (plain IMAP), 8080 (doveadm HTTP) and 9090 (metrics) are open
  inside the pod. Only 993 is published through the Service. The doveadm API
  rejects requests because `doveadm_password` is unset.

## Verification after a change

```bash
kubectl kustomize apps/mailarchive                    # renders?
kubectl -n mailarchive exec deploy/dovecot -- /dovecot/bin/doveconf -n
kubectl -n mailarchive get pvc mailarchive-data        # Bound, RWX?
kubectl -n mailarchive get svc dovecot                # EXTERNAL-IP .220?
kubectl -n mailarchive get certificate                # Ready=True?
openssl s_client -connect 192.168.10.220:993 -crlf    # from the LAN
```

# Backup Flows

This directory contains documentation for the backup flows implemented in the cluster.

## Overview

The cluster utilizes three main backup/replication mechanisms:
1.  **Velero**: For Kubernetes resource backup and PVC snapshots (specifically for Garage).
2.  **Benji**: For block-level PVC backups (generic, label-based).
3.  **Zrepl**: For ZFS filesystem replication (specifically for Garage data).

## 1. Velero Backup Flows

Velero is configured with two specific schedules targeting the `garage` namespace.

### 1.1 Garage Metadata Backup (Ceph)
*   **Schedule Name**: `garage-meta-ceph`
*   **Frequency**: Daily at 03:00
*   **Target**: PVCs in `garage` namespace with label `backup-this-pvc: "true"`
*   **Storage**: Scaleway Object Storage
*   **Mechanism**: CSI Snapshot + Data Mover (`snapshotMoveData: true`)

```mermaid
graph LR
    subgraph Cluster
        PVC[PVC (garage/backup-this-pvc=true)]
        Velero[Velero Controller]
    end
    subgraph Scaleway
        S3[Object Storage]
    end

    Velero -- Triggers --> PVC
    PVC -- Snapshot Data --> S3
```

### 1.2 Garage Data Backup (ZFS Local)
*   **Schedule Name**: `garage-data-zfs`
*   **Frequency**: Daily at 03:00
*   **Target**: PVCs in `garage` namespace with label `backup-strategy: zfs-local`
*   **Storage**: Scaleway (Metadata only), Local ZFS (Data)
*   **Mechanism**: CSI Snapshot (No Data Move, `snapshotMoveData: false`)

```mermaid
graph LR
    subgraph Cluster
        PVC[PVC (garage/backup-strategy=zfs-local)]
        Velero[Velero Controller]
        ZFS[Local ZFS Pool]
    end
    subgraph Scaleway
        S3[Object Storage]
    end

    Velero -- Triggers --> PVC
    PVC -- Snapshot --> ZFS
    Velero -- Metadata --> S3
```

## 2. Benji Backup Flow

Benji is configured to perform block-level backups of PVCs based on labels.

### 2.1 Generic PVC Backup
*   **Job Name**: `benji-backup-all`
*   **Frequency**: Daily at 07:30
*   **Target**: Any PVC with label `backup-this-pvc = true`
*   **Storage**: Ceph/S3 (Benji Backend)
*   **Retention**: Enforced by `benji-enforce` (Daily at 06:00, keeps `latest7`)

```mermaid
graph LR
    subgraph Cluster
        PVC[PVC (label: backup-this-pvc=true)]
        Benji[Benji CronJob]
    end
    subgraph Storage
        Ceph[Ceph/S3 Backend]
    end

    Benji -- Reads --> PVC
    Benji -- Writes Block Diff --> Ceph
```

## 3. Zrepl Replication Flow

Zrepl is used for continuous replication of the Garage data ZFS dataset.

### 3.1 Garage Data Replication
*   **Components**: `zrepl-garage-push` (Sender), `zrepl-sink` (Receiver)
*   **Frequency**: Periodic (Every 10 minutes)
*   **Source**: Garage Data PVC (ZFS Dataset)
*   **Target**: Backup Node (`wdc/zrepl/garage`)
*   **Pruning**:
    *   Sender: Keep last 10
    *   Receiver: Grid retention (`1x1h(keep=all) | 24x1h | 30x1d | 6x30d`)

```mermaid
graph LR
    subgraph Node A (Source)
        SourceFS[Garage Data ZFS]
        Push[zrepl-garage-push]
    end
    subgraph Node B (Backup)
        Sink[zrepl-sink]
        TargetFS[wdc/zrepl/garage]
    end

    Push -- Reads --> SourceFS
    Push -- TLS Stream --> Sink
    Sink -- Writes --> TargetFS
```


## 4. Postgres Backup Flow

Postgres is backed up using Velero with a pre-backup hook to perform a logical dump.

### 4.1 Postgres Logical Backup
*   **Schedule Name**: `postgres-backup`
*   **Frequency**: Daily at 04:00
*   **Target**: `postgres` namespace (PVCs + Pods)
*   **Storage**: Garage Object Storage
*   **Mechanism**:
    1.  **Pre-hook**: `pg_dumpall` to `/backups/dump.sql` (Ephemeral Volume).
    2.  **Backup**:
        *   **Metadata**: Kubernetes resources.
        *   **Data**: File System Backup (Restic/Kopia) of `/backups` volume.
        *   **Excluded**: Full PVC snapshots are disabled.
    3.  **Post-hook**: Delete dump file.

```mermaid
graph LR
    subgraph Cluster
        Pod[Postgres Pod]
        Ephemeral[Ephemeral Volume (/backups)]
        Velero[Velero Controller]
    end
    subgraph Garage
        S3[Object Storage]
    end

    Velero -- 1. Trigger Hook --> Pod
    Pod -- pg_dumpall --> Ephemeral
    Velero -- 2. FS Backup --> Ephemeral
    Ephemeral -- Data --> S3
    Velero -- 3. Cleanup Hook --> Pod
```

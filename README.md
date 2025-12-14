# valero_longhorn
Backup with velero and longhorn 
PC Hôte (10.0.2.2 vu depuis la VM)
    │
    └─→ MinIO (Docker)
         ├─→ Port 9001 (API)
         ├─→ Port 9091 (Console)
         ├─→ Bucket: velero (métadonnées Velero)
         └─→ Bucket: longhorn (données volumes)

VM Vagrant (192.168.56.10)
    │
    └─→ K3s v1.28.5
         ├─→ Longhorn v1.4.0
         ├─→ Snapshot Controller v5.0
         └─→ Velero v1.13.0
              ├─→ Plugin AWS v1.10.0
              └─→ Plugin CSI v0.7.1

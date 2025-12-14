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
# 1. Sur ton PC hôte : Démarrer MinIO
docker run -d --name minio-velero \
  -p 9001:9000 -p 9091:9090 \
  -e MINIO_ROOT_USER=MINIOADMIN \
  -e MINIO_ROOT_PASSWORD=MINIOADMINPW \
  -v minio-data:/data --restart unless-stopped \
  quay.io/minio/minio:latest \
  server /data --console-address ':9090'

# Configurer MinIO (http://localhost:9091)
# - Créer buckets: velero, longhorn
# - Créer Access Key: test-key / test-secret-key

# 2. Démarrer la VM
vagrant up
vagrant ssh

# 3. Lancer le script d'installation
chmod +x install-velero-longhorn.sh
./install-velero-longhorn.sh

Créer un backup
bash# Déployer une app de test
kubectl apply -f example-app.yaml

# Écrire des données
kubectl exec -n csi-app csi-nginx -- sh -c 'echo "Test GRDF" > /mnt/longhorndisk/test.txt'

# Créer le backup
velero backup create mon-backup --include-namespaces csi-app --wait

# Vérifier
velero backup describe mon-backup
kubectl get volumesnapshot -n csi-app
kubectl get backups.longhorn.io -n longhorn-system

Restaurer un backup
bash# Supprimer le namespace
kubectl delete namespace csi-app

# Restaurer
velero restore create --from-backup mon-backup --wait

# Vérifier les données
kubectl exec -n csi-app csi-nginx -- cat /mnt/longhorndisk/test.txt


# Source: https://platform.cloudogu.com/en/blog/velero-longhorn-backup-restore/

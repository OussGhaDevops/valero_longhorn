#!/bin/bash
set -e

echo "═══════════════════════════════════════════════════════"
echo "  Installation Velero + Longhorn - Configuration GRDF"
echo "═══════════════════════════════════════════════════════"
echo ""

# ============================================
# ÉTAPE 1 : MinIO sur PC hôte
# ============================================
echo "📦 ÉTAPE 1 : Démarrage MinIO sur le PC hôte"
echo ""
read -p "⚠️  Cette commande doit être exécutée sur le PC HÔTE (pas dans la VM). Continuer ? (oui/non): " confirm
if [ "$confirm" != "oui" ]; then
    echo "Exécute d'abord sur ton PC hôte :"
    echo ""
    echo "docker run -d --name minio-velero \\"
    echo "  -p 9001:9000 -p 9091:9090 \\"
    echo "  -e MINIO_ROOT_USER=MINIOADMIN \\"
    echo "  -e MINIO_ROOT_PASSWORD=MINIOADMINPW \\"
    echo "  -v minio-data:/data --restart unless-stopped \\"
    echo "  quay.io/minio/minio:latest \\"
    echo "  server /data --console-address ':9090'"
    echo ""
    echo "Puis configure MinIO (http://localhost:9091) :"
    echo "  - Créer buckets : velero, longhorn"
    echo "  - Créer Access Key : test-key / test-secret-key"
    echo ""
    exit 0
fi

# ============================================
# ÉTAPE 2 : Vérifier K3s
# ============================================
echo ""
echo "🔍 ÉTAPE 2 : Vérification K3s"
if ! kubectl get nodes &>/dev/null; then
    echo "❌ K3s n'est pas installé ou kubectl non configuré"
    exit 1
fi
echo "✅ K3s opérationnel"

# ============================================
# ÉTAPE 3 : Installer Longhorn
# ============================================
echo ""
echo "📦 ÉTAPE 3 : Installation Longhorn v1.4.0"

# Sauvegarder les fichiers de config
cat > /tmp/longhorn-values.yaml << 'EOF'
defaultSettings:
  backupTarget: s3://longhorn@us-east-1/
  backupTargetCredentialSecret: minio-secret
  defaultReplicaCount: 1
  guaranteedEngineManagerCPU: 5
  guaranteedReplicaManagerCPU: 5
  storageMinimalAvailablePercentage: 10
  backupstorePollInterval: 300

persistence:
  defaultClass: true
  defaultClassReplicaCount: 1

csi:
  attacherReplicaCount: 1
  provisionerReplicaCount: 1
  resizerReplicaCount: 1
  snapshotterReplicaCount: 1
EOF

helm repo add longhorn https://charts.longhorn.io
helm repo update

kubectl create namespace longhorn-system --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --values /tmp/longhorn-values.yaml \
  --version 1.4.0 \
  --wait --timeout 10m

echo "✅ Longhorn installé"

# ============================================
# ÉTAPE 4 : Secret MinIO pour Longhorn
# ============================================
echo ""
echo "🔐 ÉTAPE 4 : Configuration secret MinIO pour Longhorn"

cat > /tmp/longhorn-secret.yaml << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: minio-secret
  namespace: longhorn-system
type: Opaque
stringData:
  AWS_ACCESS_KEY_ID: test-key
  AWS_SECRET_ACCESS_KEY: test-secret-key
  AWS_ENDPOINTS: http://10.0.2.2:9001
  AWS_CERT: ""
  VIRTUAL_HOSTED_STYLE: "false"
EOF

kubectl apply -f /tmp/longhorn-secret.yaml
echo "✅ Secret MinIO créé"

# ============================================
# ÉTAPE 5 : Snapshot Controller
# ============================================
echo ""
echo "📸 ÉTAPE 5 : Installation Snapshot Controller v5.0"

kubectl create -k "github.com/kubernetes-csi/external-snapshotter/client/config/crd?ref=release-5.0" || true
kubectl create -k "github.com/kubernetes-csi/external-snapshotter/deploy/kubernetes/snapshot-controller?ref=release-5.0" || true

sleep 10
echo "✅ Snapshot Controller installé"

# ============================================
# ÉTAPE 6 : VolumeSnapshotClass
# ============================================
echo ""
echo "📦 ÉTAPE 6 : Création VolumeSnapshotClass"

cat > /tmp/volumesnapshotclass.yaml << 'EOF'
kind: VolumeSnapshotClass
apiVersion: snapshot.storage.k8s.io/v1
metadata:
  name: longhorn-snapshot-vsc
  labels:
    velero.io/csi-volumesnapshot-class: "true"
driver: driver.longhorn.io
deletionPolicy: Delete
parameters:
  type: bak
EOF

kubectl apply -f /tmp/volumesnapshotclass.yaml
echo "✅ VolumeSnapshotClass créée"

# ============================================
# ÉTAPE 7 : Installer Velero CLI
# ============================================
echo ""
echo "🛠️  ÉTAPE 7 : Installation Velero CLI v1.13.0"

VELERO_VERSION="v1.13.0"
wget -q https://github.com/vmware-tanzu/velero/releases/download/${VELERO_VERSION}/velero-${VELERO_VERSION}-linux-amd64.tar.gz
tar -xzf velero-${VELERO_VERSION}-linux-amd64.tar.gz -C /tmp/
sudo mv /tmp/velero-${VELERO_VERSION}-linux-amd64/velero /usr/local/bin/velero
rm -f velero-${VELERO_VERSION}-linux-amd64.tar.gz

velero version --client-only
echo "✅ Velero CLI installé"

# ============================================
# ÉTAPE 8 : Credentials Velero
# ============================================
echo ""
echo "🔑 ÉTAPE 8 : Création credentials Velero"

cat > /tmp/credentials-velero << 'EOF'
[default]
aws_access_key_id=test-key
aws_secret_access_key=test-secret-key
EOF

echo "✅ Credentials créés"

# ============================================
# ÉTAPE 9 : Installer Velero
# ============================================
echo ""
echo "🚀 ÉTAPE 9 : Installation Velero avec plugins CSI"

velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.10.0,velero/velero-plugin-for-csi:v0.7.1 \
  --bucket velero \
  --secret-file /tmp/credentials-velero \
  --use-volume-snapshots=true \
  --backup-location-config region=us-east-1,s3ForcePathStyle="true",s3Url=http://10.0.2.2:9001 \
  --snapshot-location-config region=us-east-1 \
  --features=EnableCSI

echo ""
echo "⏳ Attente démarrage Velero..."
sleep 40

kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=velero \
  -n velero \
  --timeout=120s

echo "✅ Velero installé"

# ============================================
# VÉRIFICATIONS FINALES
# ============================================
echo ""
echo "═══════════════════════════════════════════════════════"
echo "  ✅ INSTALLATION TERMINÉE"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "📊 Vérifications :"
echo ""

echo "🔹 Pods Longhorn :"
kubectl get pods -n longhorn-system | head -5

echo ""
echo "🔹 Pods Velero :"
kubectl get pods -n velero

echo ""
echo "🔹 Backup Storage Location :"
velero backup-location get

echo ""
echo "🔹 VolumeSnapshotClass :"
kubectl get volumesnapshotclass

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  🎉 PRÊT POUR LES BACKUPS !"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "📝 Prochaines étapes :"
echo "  1. Déployer une application : kubectl apply -f example-app.yaml"
echo "  2. Créer un backup : velero backup create test-1 --include-namespaces csi-app"
echo "  3. Tester le restore : velero restore create --from-backup test-1"
echo ""

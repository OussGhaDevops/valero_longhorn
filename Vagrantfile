# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  config.vm.box = "generic/ubuntu2204"
  
  config.vm.provider "virtualbox" do |vb|
    vb.memory = "4096"
    vb.cpus = 2
    vb.name = "k3s-velero-longhorn"
  end

  config.vm.network "private_network", ip: "192.168.56.10"

  config.vm.provision "shell", inline: <<-SHELL
    set -e
    
    apt-get update
    apt-get install -y curl wget git vim jq open-iscsi nfs-common ca-certificates
    
    # Installer K3s
    curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.28.5+k3s1" sh -s - \
      --write-kubeconfig-mode 644 \
      --disable traefik
    
    # Config kubectl pour vagrant
    mkdir -p /home/vagrant/.kube
    cp /etc/rancher/k3s/k3s.yaml /home/vagrant/.kube/config
    chown -R vagrant:vagrant /home/vagrant/.kube
    
    # Installer k9s
    K9S_VERSION="v0.31.7"
    wget -q https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_amd64.tar.gz
    tar -xzf k9s_Linux_amd64.tar.gz -C /tmp
    mv /tmp/k9s /usr/local/bin/
    rm k9s_Linux_amd64.tar.gz
    
    # Config réseau
    echo "10.0.2.2 host-pc minio-server" >> /etc/hosts
    
    # Installer Helm
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    
    echo "VM K3s prête !"
    kubectl get nodes
  SHELL
end

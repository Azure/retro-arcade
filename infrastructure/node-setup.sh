#!/bin/bash

export APP_ID=$1
export PASSWD=$2
export TENANT=$3
export RG=$4

echo "Starting Node Setup..."

echo "Installing Azure CLI..."
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
echo "Azure CLI Install Complete"

echo "Install kubectl..."
sudo snap install kubectl --classic
echo "kubectl Install Complete"

echo "Installing Helm3..."
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
echo "Helm3 Install Complete"

echo "Setup k3s..."
curl -sfL https://get.k3s.io | sh -
echo "k3s Setup Complete"

echo "Check k3s status"
sudo k3s kubectl cluster-info
sudo k3s kubectl get pods -A

echo "Login to Azure"
az login --service-principal --username $APP_ID --password $PASSWD --tenant $TENANT

echo "Deploy Arc to k3s"
az extension add --name connectedk8s
az extension add --name k8sconfiguration

sudo az connectedk8s connect \
--resource-group $RG \
--name k3s \
--distribution k3s \
--kube-config /etc/rancher/k3s/k3s.yaml

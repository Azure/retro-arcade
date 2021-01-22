#!/bin/bash

# Initialize Variables
export RG=EphRetroArcade
export HUB_LOC=eastus
export BRANCH_LOC=eastus
export HUB_CLUSTER_NAME=retroarcade
export K8S_VERSION=1.19.3
export ADMIN_USER=griffith

# Create Resource Group
az group create -n $RG -l $HUB_LOC

# Build Hub and Branch (On-Prem Simulation) Vnets

# Create Hub Vnet and AKS Subnet
az network vnet create \
-g $RG \
-n hub-vnet-$HUB_LOC \
--address-prefix 10.40.0.0/16 \
--subnet-name aks --subnet-prefix 10.40.0.0/24

# Create Hub Kubernetes Services Subnet
az network vnet subnet create \
    --resource-group $RG \
    --vnet-name hub-vnet-$HUB_LOC \
    --name services \
    --address-prefix 10.40.2.0/24

# Get Subnet ID
AKS_SUBNET_ID=$(az network vnet show -g $RG -n hub-vnet-$HUB_LOC -o tsv --query "subnets[?name=='aks'].id")

# Create Branch Vnet
az network vnet create \
-g $RG \
-n branch-vnet-$BRANCH_LOC \
-l $BRANCH_LOC \
--address-prefix 10.50.0.0/16 \
--subnet-name k8s-subnet --subnet-prefix 10.50.0.0/24

# Create Hub to Branch Peer
az network vnet peering create \
--resource-group $RG \
--name hubtobranch \
--remote-vnet branch-vnet-$HUB_LOC \
--vnet-name hub-vnet-$HUB_LOC

# Create Branch to Hub Peer
az network vnet peering create \
--resource-group $RG \
--name branchtohub \
--remote-vnet hub-vnet-$HUB_LOC \
--vnet-name branch-vnet-$HUB_LOC

# Create Hub AKS Cluster
az aks create \
-g $RG \
-n $HUB_CLUSTER_NAME \
--vnet-subnet-id $AKS_SUBNET_ID \
--network-plugin azure \
--enable-addons monitoring \
--kubernetes-version $K8S_VERSION

# Get Cluster Admin Credentials
az aks get-credentials -g $RG -n $HUB_CLUSTER_NAME

# Create remote vm and load with k3s
az vm create \
--resource-group $RG \
--name k3s-host \
--admin-username $ADMIN_USER \
--vnet-name branch-vnet-$BRANCH_LOC \
--authentication-type ssh \
--nsg-rule SSH \
--ssh-key-values @~/.ssh/id_rsa.pub \
--subnet k8s-subnet \
--image UbuntuLTS 

# Setup k3s main
az vm run-command invoke \
-g $RG \
-n k3s-main \
--command-id RunShellScript \
--scripts "curl -sfL https://get.k3s.io | sh -"

################################################
# After the node is up you still need to run the following
# steps that I need to automate
#########################################################

# Install Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

# Copy the kube config file over to .kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config

# Install Helm3
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

# Login to Azure and arc connect
az login
az set account -s <SubID>
sudo az connectedk8s connect --name k3s --resource-group EphRetroArcade
 
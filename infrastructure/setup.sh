#!/bin/bash

# Initialize Variables
export RG=EphRetroArcade
export HUB_LOC=eastus
export BRANCH_LOC=eastus
export HUB_CLUSTER_NAME=retroarcade
export K8S_VERSION=1.19.3
export ADMIN_USER=<Insert Admin User>
export ADMIN_PASSWD=<Insert Admin Password>

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
--admin-password $ADMIN_PASSWD \
--vnet-name branch-vnet-$BRANCH_LOC \
--authentication-type password \
--nsg-rule SSH \
--subnet k8s-subnet \
--image UbuntuLTS 

export SP_JSON=$(az ad sp create-for-rbac --skip-assignment -o json)
echo $SP_JSON
export APPID=$(echo $SP_JSON | jq -r .appId)
echo "AppID: $APPID"
export APPPASSWD=$(echo $SP_JSON | jq -r .password)
echo "App Psswd: $APPPASSWD"
export TENANT=$(echo $SP_JSON | jq -r .tenant)
echo "Tenant: $TENANT"

read -t 10 -p "Pause for 10 sec while service principal propegates ..."

az role assignment create --assignee $APPID \
--role "Contributor" \
--resource-group $RG

# Setup k3s main
az vm run-command invoke \
-g $RG \
-n k3s-host \
--command-id RunShellScript \
--scripts "wget https://raw.githubusercontent.com/Azure/retro-arcade/infra/infrastructure/node-setup.sh; chmod +x node-setup.sh; ./node-setup.sh $APPID ""$APPPASSWD"" $TENANT $RG"

az k8sconfiguration create \
--cluster-name k3s \
--cluster-type connectedClusters \
--name steelwire \
--repository-url https://github.com/swgriffith/clippyfunc.git \
--resource-group $RG \
--scope cluster \
--operator-instance-name steelwire-config --operator-namespace steelwire-config \
--operator-params="--git-branch master --git-readonly --git-path=manifests --sync-garbage-collection" 



$environmentName = "zerotohero"
$kubernetesClusterName = "aks-$environmentName"
$aadGroup = "aks-admin-group"
$tagValue = "AKS"
$location = "West Europe"
$containerRegistryName =  "acr$environmentname" -replace '[-]'
$k8sver = (az aks get-versions -l $location --query 'orchestrators[-3].orchestratorVersion' -o tsv)
$vmNodeSize = "Standard_DS2_v2"
$linuxNodePoolName = "linux1"
$nodeCount = 2

<# Resource Groups #>
$resourceGroupNameAKS = "rg-aks-$environmentName"
$nodeResourceGroup = "rg-aks-nodes-$environmentName"
$resourceGroupNameMonitoring = "rg-shared-$environmentName"
$resourceGroupNameACR = $resourceGroupNameMonitoring


$monitoringWorkspaceName = "wsaks$environmentName"

<# vNet variables #>
$vnetName = "vnet-$environmentName"


<# Resource Groups #>
az group create --name $resourceGroupNameAKS --location $location
az group create --name $resourceGroupNameMonitoring --location $location


<# Create vNet #>
az network vnet create `
    --name $vnetName `
    --resource-group $resourceGroupNameAKS `
    --address-prefix 10.240.0.0/16 `
    --subnet-name clusternodes `
    --subnet-prefix 10.240.0.0/20 `
    --location $location `
    --tags Environment=$tagValue 

    az network vnet subnet create `
    --resource-group $resourceGroupNameAKS `
    --vnet-name $vnetName `
    --name clusteringservices `
    --address-prefixes 10.240.16.0/28 

    az network vnet subnet create `
    --resource-group $resourceGroupNameAKS `
    --vnet-name $vnetName `
    --name applicationgateway `
    --address-prefixes 10.240.16.16/28
    
<# Create Container Registry #>
az acr create `
    --name $containerRegistryName `
    --resource-group $resourceGroupNameACR `
    --sku Basic `
    --tags Environment=$tagValue

<# Create Log Analytics #>
az monitor log-analytics workspace create `
    --resource-group $resourceGroupNameMonitoring `
    --workspace-name $monitoringWorkspaceName `
    --sku PerGB2018 `
    --location $location `
    --tags Environment=$tagValue

<# AKS preview extension - needed for node resource group name #>
az extension add --name aks-preview
<# Create AKS #>
$subid = az network vnet subnet show --resource-group $resourceGroupNameAKS --vnet-name $vnetName --name clusternodes --query id
$resourceIdMonitoring = az resource list --name $monitoringWorkspaceName --query [].id --output tsv
az aks create `
    --resource-group $resourceGroupNameAKS `
    --name $kubernetesClusterName `
    --node-count $nodeCount `
    --nodepool-name $linuxNodePoolName `
    --node-vm-size $vmNodeSize `
    --node-resource-group $nodeResourceGroup `
    --generate-ssh-keys `
    --network-plugin azure `
    --enable-managed-identity `
    --enable-cluster-autoscaler `
    --min-count $nodeCount `
    --max-count 10 `
    --vnet-subnet-id $subid `
    --zones 1 2 3 `
    --kubernetes-version $k8sver `
    --node-osdisk-type Ephemeral `
    --node-osdisk-size 80 `
    --enable-addons monitoring `
    --workspace-resource-id $resourceIdMonitoring `
    --tags Environment=$tagValue

<# attach ACR #>
$acrid = az acr show --name $containerRegistryName --query id --output tsv
az aks update `
    --resource-group $resourceGroupNameAKS `
    --name $kubernetesClusterName `
    --attach-acr $acrid

<# Integrate Azure AD #>
$groupID = az ad group show --group $aadGroup --query objectId --output tsv
az aks update `
    --resource-group $resourceGroupNameAKS `
    --name $kubernetesClusterName `
    --enable-aad `
    --aad-admin-group-object-ids $groupID

<# Get KubeConfig #>
az aks get-credentials -g $resourceGroupNameAKS -n $kubernetesClusterName

<# Kubectl get nodes #>
Kubectl get nodes
kubelogin convert-kubeconfig -l azurecli
az aks get-credentials -g myaks-rg --name myakscluster

az aks update  -g myaks-rg --name myakscluster --node-provisioning-mode Auto
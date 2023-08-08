#!/bin/bash

echo " Prepare to install Helm for PX -Backup Install"
kubectl create namespace central
kubectl apply -f px-sc.yaml
sleep 10
helm repo add portworx http://charts.portworx.io/ && helm repo update
sleep 5

echo " Install PX -Backup"

helm install px-central portworx/px-central --namespace central --create-namespace --version 2.2.1 --set persistentStorage.enabled=true,persistentStorage.storageClassName="portworx-sc",pxbackup.enabled=true

#old
#helm install px-central portworx/px-central --namespace central --set persistentStorage.enabled=true,persistentStorage.storageClassName="portworx-sc",pxbackup.enabled=true

sleep 5

while true; do
    NUM_READY=`kubectl get po --namespace central -ljob-name=pxcentral-post-install-hook  -o wide | awk '{print $1, $3}' | grep -iv error | awk '{print $2}' | tail -1`
    if [ "${NUM_READY}" == "Completed" ]; then
        echo "PX Backup Installed!"
        break
    else
        echo "Waiting for PX Backup to be ready. Status: ${NUM_READY}"
    fi
    sleep 5
done

echo " 1. Connect to PX-Backup GUI - http://10.0.0.30:<svc-port>/ : Credentials: admin:admin"
echo " 2. Add PX Cluster"
echo " 3. K8 Platform: Others"
echo " 4. Clustername- px-cluster-local"
echo " 5. Copy paste output : kubectl config view --flatten --minify"
echo " 6. K8 services - others"

#!/bin/bash

echo "PX 3.0 Deployment Script Running on FA Cloud Volumes"
sleep 1

echo "Checking K8 Nodes are Ready"
while true; do    
	NUM_READY=`kubectl get nodes 2> /dev/null | grep -v NAME | awk '{print $2}' | grep -e ^Ready | wc -l`
    if [ "${NUM_READY}" == "4" ]; then
        echo "All ${NUM_READY} Kubernetes nodes are ready !"
        break
    else
        echo "Waiting for all Kubernetes nodes to be ready. Current ready nodes: ${NUM_READY}"
        kubectl get nodes
    fi
    sleep 5
done

echo "Make Sure you're at the master node home directory: /home/pureuser"

echo " Create namespace called portworx"
kubectl create ns portworx
sleep 2
kubectl get ns -A
sleep 5

echo " Step 1. Verify JSON file FA API token from home directory:"
cat pure.json
sleep 10

echo " Step 2. Create Kubernetes Secret called px-pure-secret:"
kubectl create secret generic px-pure-secret --namespace portworx --from-file=pure.json
sleep 2
kubectl get secrets -A | grep px-pure-secret
sleep 5


echo " Step 3. Install PX Operator and check if the POD is running:"
kubectl apply -f 'https://install.portworx.com/3.1?comp=pxoperator&kbver=1.28.5&ns=portworx'
while true; do
    NUM_READY=`kubectl get pods -n portworx -o wide | grep portworx-operator | grep Running | wc -l`
    if [ "${NUM_READY}" == "1" ]; then
        echo "PX Operator pod is ready!"
        kubectl get pods -n portworx -o wide | grep portworx-operator | grep Running
        break
    else
        echo "Waiting for PX Operator POD to be ready. Current ready pods: ${NUM_READY}"
    fi
    sleep 5
done
sleep 2

echo " Step 4. Install PortWorx 3.1 Spec using FlashArray Cloud Drives:"
sleep 5
#kubectl apply -f px-spec-3.0.yaml
kubectl apply -f 'https://install.portworx.com/3.1?operator=true&mc=false&kbver=1.28.5&ns=portworx&b=true&iop=6&s=%22size%3D150%22&pureSanType=ISCSI&ce=pure&c=px-cluster-b585985e-eddb-4172-ab38-62f8c803175a&stork=true&csi=true&mon=true&tel=true&st=k8s&promop=true'

echo " Step 5. Wait for Portworx Installation to complete:"
while true; do
    NUM_READY=`kubectl get pods -n portworx -l name=portworx -o wide | grep Running | grep 1/1 | wc -l`
    if [ "${NUM_READY}" == "3" ]; then
        echo "All portworx nodes are ready !"
        kubectl get pods -n portworx -l name=portworx -o wide
        break
    else
        echo "Waiting for portworx nodes to be ready. Current ready nodes: ${NUM_READY}"
    fi
    sleep 5
done
echo " Checking Portworx Status"
PX_POD=$(kubectl get pods -l name=portworx -n portworx -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it $PX_POD -n portworx -- /opt/pwx/bin/pxctl status
sleep 5

#########################
echo "Installing GRAFANA"


kubectl -n portworx create configmap grafana-dashboard-config --from-file=grafana-dashboard-config.yaml
sleep 5

kubectl -n portworx create configmap grafana-source-config --from-file=grafana-datasource.yaml
sleep 5

curl "https://docs.portworx.com/samples/k8s/pxc/portworx-cluster-dashboard.json" -o portworx-cluster-dashboard.json && \
curl "https://docs.portworx.com/samples/k8s/pxc/portworx-node-dashboard.json" -o portworx-node-dashboard.json && \
curl "https://docs.portworx.com/samples/k8s/pxc/portworx-volume-dashboard.json" -o portworx-volume-dashboard.json && \
curl "https://docs.portworx.com/samples/k8s/pxc/portworx-performance-dashboard.json" -o portworx-performance-dashboard.json && \
curl "https://docs.portworx.com/samples/k8s/pxc/portworx-etcd-dashboard.json" -o portworx-etcd-dashboard.json && \
kubectl -n portworx create configmap grafana-dashboards --from-file=portworx-cluster-dashboard.json --from-file=portworx-performance-dashboard.json --from-file=portworx-node-dashboard.json --from-file=portworx-volume-dashboard.json --from-file=portworx-etcd-dashboard.json
sleep 5

kubectl apply -f grafana.yaml

sleep 10

echo " Step 6. Login to the FlashArray and verify the Cloud Volumes have been created - http://10.0.0.11"
echo " Step 7. Configure Grafana using default user: admin | password: admin - http://10.0.0.30:30196"

echo "Do you wish to install storkctl?"
select yn in "Yes" "No"; do
    case $yn in
        Yes ) echo "installing storkctl"; break;;
        No ) echo "Portworx Installation Complete!!!!"; exit;;
    esac
done

sleep 2
echo "sudo password=pureuser"

STORK_POD=$(kubectl get pods -n portworx -l name=stork -o jsonpath='{.items[0].metadata.name}') &&
kubectl cp -n portworx $STORK_POD:/storkctl/linux/storkctl ./storkctl
sudo mv storkctl /usr/local/bin &&
sudo chmod +x /usr/local/bin/storkctl

sleep 2

storkctl version

#########################
echo "Do you wish to install PX Central?"
select yn in "Yes" "No"; do
    case $yn in
        Yes ) echo "installing px-central"; break;;
        No ) echo "Portworx Installation Complete!!!!"; exit;;
    esac
done
sleep 2
helm repo add portworx http://charts.portworx.io/ && helm repo update

sleep 2
helm install px-central portworx/px-central --namespace central --create-namespace --version 2.7.1 --set persistentStorage.enabled=true,persistentStorage.storageClassName="px-replicated"
while true; do
    NUM_READY=`kubectl get po --namespace central -ljob-name=pxcentral-post-install-hook  -o wide | awk '{print $3}' | grep -iv error`
    if [ "${NUM_READY}" == "Completed" ]; then
        echo "PX Central pods are ready !"
        kubectl get pods -n central -o wide
        break
    else
        echo "Waiting for px-central nodes to be ready. Current ready nodes: ${NUM_READY}"
    fi
    sleep 5
done

helm get values --namespace central px-central -o yaml > values-px-upgrade.yaml && kubectl delete job pxcentral-post-install-hook --namespace central && helm upgrade px-central portworx/px-central --namespace central --version 2.7.1 --set pxlicenseserver.enabled=true,pxmonitor.enabled=true,persistentStorage.enabled=true,persistentStorage.storageClassName="sc-portworx-fa-direct-access",installCRDs=true,pxmonitor.pxCentralEndpoint=10.0.0.30,pxmonitor.sslEnabled=true,images.pullSecrets[0]=docregistry-secret -f values-px-upgrade.yaml
sleep 2
kubectl get svc -n central

echo "Update svc of "px-central-ui" to NodePort"
echo "run command below"
echo "kubectl edit svc px-central-ui -n central"
echo "PX Central Install Complete"

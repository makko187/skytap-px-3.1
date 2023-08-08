
echo "Do you wish to install storkctl?"
select yn in "Yes" "No"; do
    case $yn in
        Yes ) echo "installing storkctl"; break;;
        No ) echo "Portworx Installation Done"; exit;;
    esac
done

sleep 2

STORK_POD=$(kubectl get pods -n portworx -l name=stork -o jsonpath='{.items[0].metadata.name}') &&
kubectl cp -n portworx $STORK_POD:/storkctl/linux/storkctl ./storkctl
sudo mv storkctl /usr/local/bin &&
sudo chmod +x /usr/local/bin/storkctl

sleep 2

storkctl version


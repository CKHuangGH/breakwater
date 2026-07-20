#!/bin/bash

curl -s https://raw.githubusercontent.com/karmada-io/karmada/master/hack/install-cli.sh | sudo INSTALL_CLI_VERSION=1.18.1 bash

kubectl config use-context cluster0

# for i in $(cat node_exec)
# do
#     ssh root@$i kubectl taint nodes --all node-role.kubernetes.io/control-plane:NoSchedule-
# done

karmadactl init

for i in range(10, 0, -1):
    print(f"\rCountdown: {i} seconds", end="", flush=True)
    time.sleep(1)

cluster=1
for i in $(cat cp_node_list_without_management)
do
    karmadactl --kubeconfig /etc/karmada/karmada-apiserver.config  join cluster$cluster --cluster-kubeconfig=$HOME/.kube/cluster$cluster &
	cluster=$((cluster+1))
done

wait
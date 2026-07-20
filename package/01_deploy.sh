export DEBIAN_FRONTEND=noninteractive

sudo apt-get install -y screen=4.9.1-3
sudo apt-get install -y chrony=4.6.1-3+deb13u1

number=$(($(wc -l < cp_node_list) - 1))

for i in `seq 0 $number`
do
    sed -i 's/kubernetes-admin/k8s-admin-cluster'$i'/g' ~/.kube/cluster$i
    sed -i 's/name: kubernetes/name: cluster'$i'/g' ~/.kube/cluster$i
    sed -i 's/cluster: kubernetes/cluster: cluster'$i'/g' ~/.kube/cluster$i
done

for i in `seq 0 $number`
do
    string=$string"/root/.kube/cluster$i:"
done

string=$string | sed "s/.$//g"
KUBECONFIG=$string kubectl config view --flatten > ~/.kube/config

for i in `seq 0 $number`
do
    kubectl config rename-context k8s-admin-cluster$i@kubernetes cluster$i
done

sleep 5

while IFS= read -r ip_address; do
  scp -o StrictHostKeyChecking=no ./all_node_list root@$ip_address:/root/
  scp -o StrictHostKeyChecking=no ./script/chrony.sh root@$ip_address:/root/
done < "all_node_list"

while IFS= read -r ip_address; do
  ssh -n -o StrictHostKeyChecking=no root@"$ip_address" mkdir /var/log/chrony
  ssh -n -o StrictHostKeyChecking=no root@"$ip_address" sudo apt-get install -y chrony=4.6.1-3+deb13u1
  ssh -n -o StrictHostKeyChecking=no root@"$ip_address" "nohup bash /root/chrony.sh 2>&1 &"
done < "all_node_list"

wait

cluster=1
tail -n +2 cp_node_list > cp_node_list_without_management
while read -r ip; do
	scp -o StrictHostKeyChecking=no /root/.kube/config root@$ip:/root/.kube
	ssh -n -o StrictHostKeyChecking=no root@$ip chmod 777 /root/interlock/package/script/member_clusters.sh
	ssh -n -o StrictHostKeyChecking=no root@$ip bash /root/interlock/package/script/member_clusters.sh $cluster &
	cluster=$((cluster+1))
done < "cp_node_list_without_management"

wait

helm repo add cilium https://helm.cilium.io/
helm repo update
helm install cilium cilium/cilium \
  --version 1.19.5 \
  --namespace kube-system \
  --wait \
  --set operator.replicas=1 \
  --set operator.nodeSelector."node-role\.kubernetes\.io/control-plane"="" \
  --set operator.tolerations[0].key=node-role.kubernetes.io/control-plane \
  --set operator.tolerations[0].operator=Exists \
  --set operator.tolerations[0].effect=NoSchedule \
  --set operator.tolerations[1].key=node.kubernetes.io/not-ready \
  --set operator.tolerations[1].operator=Exists \
  --set operator.tolerations[1].effect=NoSchedule \
  --set operator.tolerations[2].key=node.kubernetes.io/unreachable \
  --set operator.tolerations[2].operator=Exists \
  --set operator.tolerations[2].effect=NoExecute

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install prom prometheus-community/kube-prometheus-stack \
  --version 87.6.0 \
  --namespace monitoring \
  --wait \
  --create-namespace \
  --set grafana.enabled=false \
  --set alertmanager.enabled=false \
  --set prometheus.service.type=NodePort \
  --set prometheus.prometheusSpec.scrapeInterval="5s" \
  --set prometheus.prometheusSpec.enableAdminAPI=true \
  --set prometheus.prometheusSpec.resources.requests.cpu="1000m" \
  --set prometheus.prometheusSpec.resources.requests.memory="1024Mi"

cp cp_node_list_without_management ./exps/motivation/cp_node_list_without_management
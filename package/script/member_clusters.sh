#!/bin/bash
number=$1

kubectl config use-context cluster$number

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
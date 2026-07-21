#!/usr/bin/env bash

set -euo pipefail

mkdir -p results

for run in 1 2 3 4 5
do
    echo "========================================"
    echo "Starting run ${run}"
    echo "========================================"

    kubectl --context cluster0 delete namespace motivation --ignore-not-found=true --wait=true

    kubectl --kubeconfig /etc/karmada/karmada-apiserver.config delete namespace motivation --ignore-not-found=true --wait=true

    kubectl --context cluster1 delete namespace motivation --ignore-not-found=true --wait=true

    kubectl --context cluster2 delete namespace motivation --ignore-not-found=true --wait=true

    kubectl --kubeconfig /etc/karmada/karmada-apiserver.config create namespace motivation

    kubectl --kubeconfig /etc/karmada/karmada-apiserver.config -n motivation apply -f script/online-boutique-duplicated-policy.yaml

    kubectl --kubeconfig /etc/karmada/karmada-apiserver.config -n motivation apply -f script/kubernetes-manifests.yaml

    until kubectl --context cluster1 -n motivation get deployment frontend >/dev/null 2>&1; do sleep 5; done

    until kubectl --context cluster2 -n motivation get deployment frontend >/dev/null 2>&1; do sleep 5; done

    kubectl --context cluster1 -n motivation wait --for=condition=Available deployment --all --timeout=600s

    kubectl --context cluster2 -n motivation wait --for=condition=Available deployment --all --timeout=600s

    frontendIP=$(kubectl --context cluster1 get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

    kubectl --context cluster0 create namespace motivation

    kubectl --context cluster0 -n motivation create configmap k6-script --from-file=test.js=script/k6-test.js

    sed "s|http://frontend:80|http://${frontendIP}:30080|g" script/k6-pod.yaml | kubectl --context cluster0 -n motivation apply -f -

    kubectl --context cluster0 -n motivation wait --for=condition=Ready pod/k6 --timeout=180s

    until kubectl --context cluster0 -n motivation exec k6 -- test -f /results/done >/dev/null 2>&1; do sleep 5; done

    mkdir -p results/run-${run}

    kubectl --context cluster0 -n motivation logs k6 | tee results/run-${run}/k6.log

    kubectl --context cluster0 -n motivation exec k6 -- cat /results/k6.json > results/run-${run}/k6.json

    kubectl --context cluster0 -n motivation exec k6 -- cat /results/k6-summary.json > results/run-${run}/k6-summary.json

    kubectl --context cluster1 -n motivation get pods -o wide > results/run-${run}/cluster1-pods.txt

    kubectl --context cluster2 -n motivation get pods -o wide > results/run-${run}/cluster2-pods.txt

    kubectl --kubeconfig /etc/karmada/karmada-apiserver.config -n motivation get resourcebindings.work.karmada.io -o wide > results/run-${run}/resourcebindings.txt

    kubectl --context cluster0 delete namespace motivation --wait=true

    kubectl --kubeconfig /etc/karmada/karmada-apiserver.config delete namespace motivation --wait=true

    kubectl --context cluster1 delete namespace motivation --ignore-not-found=true --wait=true

    kubectl --context cluster2 delete namespace motivation --ignore-not-found=true --wait=true

    echo "========================================"
    echo "Completed run ${run}"
    echo "========================================"
done
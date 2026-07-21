#!/usr/bin/env bash

set -euo pipefail

mkdir -p results/failover

for run in 1 2 3 4 5
do
    echo "Run ${run}/5"

    kubectl --context cluster0 delete namespace motivation --ignore-not-found=true --wait=true

    kubectl --kubeconfig /etc/karmada/karmada-apiserver.config delete namespace motivation --ignore-not-found=true --wait=true

    kubectl --context cluster1 delete namespace motivation --ignore-not-found=true --wait=true

    kubectl --context cluster2 delete namespace motivation --ignore-not-found=true --wait=true

    kubectl --kubeconfig /etc/karmada/karmada-apiserver.config create namespace motivation

    kubectl --kubeconfig /etc/karmada/karmada-apiserver.config -n motivation apply -f script/online-boutique-duplicated-policy.yaml

    kubectl --kubeconfig /etc/karmada/karmada-apiserver.config -n motivation apply -f script/primary-full-capacity.yaml

    kubectl --kubeconfig /etc/karmada/karmada-apiserver.config -n motivation apply -f script/kubernetes-manifests.yaml

    until kubectl --context cluster1 -n motivation get deployment frontend >/dev/null 2>&1; do sleep 5; done

    until kubectl --context cluster2 -n motivation get deployment frontend >/dev/null 2>&1; do sleep 5; done

    kubectl --context cluster1 -n motivation wait --for=condition=Available deployment --all --timeout=600s

    kubectl --context cluster2 -n motivation wait --for=condition=Available deployment --all --timeout=600s

    sleep 60

    cluster1IP=$(kubectl --context cluster1 get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

    cluster2IP=$(kubectl --context cluster2 get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

    kubectl --context cluster0 create namespace motivation

    sed -e "s|CLUSTER1_IP|${cluster1IP}|g" -e "s|CLUSTER2_IP|${cluster2IP}|g" script/haproxy.cfg > /tmp/haproxy.cfg

    kubectl --context cluster0 -n motivation create configmap haproxy-config --from-file=haproxy.cfg=/tmp/haproxy.cfg

    kubectl --context cluster0 -n motivation apply -f script/haproxy.yaml

    kubectl --context cluster0 -n motivation rollout status deployment/boutique-haproxy --timeout=180s

    sed -E "s/rate: [0-9]+,/rate: 60,/; s/duration: '[^']+',/duration: '6m',/" script/k6-test.js > /tmp/k6-test.js

    kubectl --context cluster0 -n motivation create configmap k6-script --from-file=test.js=/tmp/k6-test.js

    kubectl --context cluster0 -n motivation apply -f script/k6-pod.yaml

    kubectl --context cluster0 -n motivation wait --for=condition=Ready pod/k6 --timeout=180s

    mkdir -p results/failover/run-${run}

    echo "event,timestamp" > results/failover/run-${run}/timeline.csv

    kubectl --context cluster0 -n motivation exec k6 -- sh -c 'k6 run --out json=/results/k6.json --summary-export=/results/k6-summary.json /scripts/test.js > /results/k6.log 2>&1; touch /results/done' >/dev/null 2>&1 &

    echo "test_start,$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> results/failover/run-${run}/timeline.csv

    (
        echo "timestamp,frontend_ready,currency_ready,recommendation_ready"

        until kubectl --context cluster0 -n motivation exec k6 -- test -f /results/done >/dev/null 2>&1
        do
            echo "$(date -u +%Y-%m-%dT%H:%M:%SZ),$(kubectl --context cluster2 -n motivation get deployment frontend -o jsonpath='{.status.readyReplicas}'),$(kubectl --context cluster2 -n motivation get deployment currencyservice -o jsonpath='{.status.readyReplicas}'),$(kubectl --context cluster2 -n motivation get deployment recommendationservice -o jsonpath='{.status.readyReplicas}')"

            sleep 1
        done
    ) > results/failover/run-${run}/c2-replicas.csv &

    sleep 60

    echo "failover,$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> results/failover/run-${run}/timeline.csv

    kubectl --context cluster0 -n motivation exec deployment/boutique-haproxy -c control -- sh -c "echo 'set server online_boutique_clusters/c1 state maint' | socat - UNIX-CONNECT:/var/run/haproxy/admin.sock"

    kubectl --kubeconfig /etc/karmada/karmada-apiserver.config -n motivation apply -f script/backup-capacity-recovery.yaml

    echo "recovery_started,$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> results/failover/run-${run}/timeline.csv

    until kubectl --context cluster0 -n motivation exec k6 -- test -f /results/done >/dev/null 2>&1; do sleep 5; done

    echo "test_end,$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> results/failover/run-${run}/timeline.csv

    wait

    kubectl --context cluster0 -n motivation exec k6 -- cat /results/k6.json > results/failover/run-${run}/k6.json

    kubectl --context cluster0 -n motivation exec k6 -- cat /results/k6-summary.json > results/failover/run-${run}/k6-summary.json

    kubectl --context cluster0 delete namespace motivation --wait=true

    kubectl --kubeconfig /etc/karmada/karmada-apiserver.config delete namespace motivation --wait=true

    kubectl --context cluster1 delete namespace motivation --ignore-not-found=true --wait=true

    kubectl --context cluster2 delete namespace motivation --ignore-not-found=true --wait=true

    rm -f /tmp/haproxy.cfg /tmp/k6-test.js
done
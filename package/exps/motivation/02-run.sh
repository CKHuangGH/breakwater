#!/usr/bin/env bash

set -euo pipefail

mkdir -p results/normal
mkdir -p results/failover

for mode in normal failover
do
    for run in 1 2 3 4 5
    do
        echo "Mode=${mode} Run=${run}/5"

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

        for deployment in emailservice checkoutservice recommendationservice frontend paymentservice productcatalogservice cartservice currencyservice shippingservice adservice redis-cart
        do
            kubectl --context cluster1 -n motivation rollout status deployment/${deployment} --timeout=600s
            kubectl --context cluster2 -n motivation rollout status deployment/${deployment} --timeout=600s
        done

        sleep 30

        cluster1IP=$(kubectl --context cluster1 get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
        cluster2IP=$(kubectl --context cluster2 get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

        kubectl --context cluster0 create namespace motivation

        sed -e "s|CLUSTER1_IP|${cluster1IP}|g" -e "s|CLUSTER2_IP|${cluster2IP}|g" script/haproxy.cfg > /tmp/haproxy-${mode}-${run}.cfg

        kubectl --context cluster0 -n motivation create configmap haproxy-config --from-file=haproxy.cfg=/tmp/haproxy-${mode}-${run}.cfg
        kubectl --context cluster0 -n motivation apply -f script/haproxy.yaml
        kubectl --context cluster0 -n motivation rollout status deployment/boutique-haproxy --timeout=180s

        kubectl --context cluster0 -n motivation create configmap k6-script --from-file=test.js=script/k6-test.js
        kubectl --context cluster0 -n motivation apply -f script/k6-pod.yaml
        kubectl --context cluster0 -n motivation wait --for=condition=Ready pod/k6 --timeout=180s

        mkdir -p results/${mode}/run-${run}
        echo "event,timestamp" > results/${mode}/run-${run}/timeline.csv
        echo "timestamp,ready_replicas,desired_replicas" > results/${mode}/run-${run}/c2-replicas.csv

        echo "test_start,$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" >> results/${mode}/run-${run}/timeline.csv

        kubectl --context cluster0 -n motivation exec k6 -- sh -c 'rm -f /results/done /results/k6.json /results/k6-summary.json /results/k6.log; k6 run --env RATE=60 --env DURATION=6m --out json=/results/k6.json --summary-export=/results/k6-summary.json /scripts/test.js > /results/k6.log 2>&1; touch /results/done' >/dev/null 2>&1 &

        (
            until kubectl --context cluster0 -n motivation exec k6 -- test -f /results/done >/dev/null 2>&1
            do
                readyReplicas=0
                desiredReplicas=0

                for deployment in emailservice checkoutservice recommendationservice frontend paymentservice productcatalogservice cartservice currencyservice shippingservice adservice
                do
                    ready=$(kubectl --context cluster2 -n motivation get deployment ${deployment} -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
                    desired=$(kubectl --context cluster2 -n motivation get deployment ${deployment} -o jsonpath='{.spec.replicas}' 2>/dev/null || true)
                    readyReplicas=$((readyReplicas + ${ready:-0}))
                    desiredReplicas=$((desiredReplicas + ${desired:-0}))
                done

                echo "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ),${readyReplicas},${desiredReplicas}" >> results/${mode}/run-${run}/c2-replicas.csv
                sleep 1
            done
        ) &

        if [ "${mode}" = "failover" ]
        then
            sleep 60

            echo "failover,$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" >> results/${mode}/run-${run}/timeline.csv
            kubectl --context cluster0 -n motivation exec deployment/boutique-haproxy -c control -- sh -c "printf 'set server online_boutique_clusters/c1 state maint\n' | socat - UNIX-CONNECT:/var/run/haproxy/admin.sock"

            kubectl --kubeconfig /etc/karmada/karmada-apiserver.config -n motivation apply -f script/backup-capacity-recovery.yaml
            echo "recovery_policy_applied,$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" >> results/${mode}/run-${run}/timeline.csv
        fi

        until kubectl --context cluster0 -n motivation exec k6 -- test -f /results/done >/dev/null 2>&1; do sleep 5; done

        wait

        echo "test_end,$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" >> results/${mode}/run-${run}/timeline.csv

        kubectl --context cluster0 -n motivation exec k6 -- cat /results/k6.json > results/${mode}/run-${run}/k6.json
        kubectl --context cluster0 -n motivation exec k6 -- cat /results/k6-summary.json > results/${mode}/run-${run}/k6-summary.json

        kubectl --context cluster0 delete namespace motivation --wait=true
        kubectl --kubeconfig /etc/karmada/karmada-apiserver.config delete namespace motivation --wait=true
        kubectl --context cluster1 delete namespace motivation --ignore-not-found=true --wait=true
        kubectl --context cluster2 delete namespace motivation --ignore-not-found=true --wait=true

        rm -f /tmp/haproxy-${mode}-${run}.cfg
    done
done

#!/bin/bash
set -e

pids=()

python3 ./cluster/vm-management-cluster.py
# pids+=($!)
# sleep 30

# python3 ./cluster/vm-member-cluster-1.py &
# pids+=($!)

# python3 ./cluster/vm-member-cluster-2.py &
# pids+=($!)

# python3 ./cluster/vm-member-cluster-3.py &
# pids+=($!)

# echo "Waiting for all VM installation clusters..."

# for pid in "${pids[@]}"; do
#     wait "$pid"
# done

echo "All VM clusters finished. Waiting 45 seconds for system stabilization..."

total=45
for ((elapsed=0; elapsed<=total; elapsed++)); do
    remaining=$((total - elapsed))
    percent=$((elapsed * 100 / total))
    filled=$((percent / 2))
    empty=$((50 - filled))

    bar=$(printf "%${filled}s" | tr ' ' '#')
    space=$(printf "%${empty}s")

    printf "\r[%s%s] %3d%% | %3d sec remaining" "$bar" "$space" "$percent" "$remaining"
    sleep 1
done
. ./02_system_ready.sh
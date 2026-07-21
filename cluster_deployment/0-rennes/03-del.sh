pids=()

python3 ./delcluster/vm-management-cluster.py &
pids+=($!)

python3 ./delcluster/vm-member-cluster-1.py &
pids+=($!)

python3 ./delcluster/vm-member-cluster-2.py &
pids+=($!)

python3 ./delcluster/vm-member-cluster-3.py &
pids+=($!)

echo "Waiting for all VM installation clusters..."

for pid in "${pids[@]}"; do
    wait "$pid"
done
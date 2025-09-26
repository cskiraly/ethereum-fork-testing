#!/bin/bash

# This script is used to test the fork transition in a Kurtosis enclave.
# It loads a kurtosis setup and a network configuration timeline, runs these
# while collecting logs and analyzing results.

# Usage: ./testfork.sh <config-file> <timing-script>

#process command line arguments
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <config-file> <timing-script>"
    exit 1
fi
config_file="$1"
timing_script="$2"

if [ ! -f "$config_file" ]; then
    echo "Config file '$config_file' not found!"
    exit 1
fi
if [ ! -f "$timing_script" ]; then
    echo "Timing script '$timing_script' not found!"
    exit 1
fi

enclave_name="test-fusaka-transition"
logfile="${config_file%.*}.log"

set -e
set -o pipefail

kill_silent() {
    kill "$@" 2>/dev/null || true
}

# add trap to catch exit signals and stop the enclave and background scripts
trap 'kill_silent $timing_pid; kill_silent $progress_pid; kurtosis enclave stop $enclave_name' EXIT

# get timing from the config file
# format:
## network_params:
##   fulu_fork_epoch: 1
##   bpo_1_epoch: 2
##   bpo_1_max_blobs: 48
##   bpo_1_target_blobs: 48
##   withdrawal_type: "0x02"
##   genesis_delay: 40
##   seconds_per_slot: 6

genesis_delay=$(grep 'genesis_delay:' $config_file | awk '{print $2}')
seconds_per_slot=$(grep 'seconds_per_slot:' $config_file | awk '{print $2}')
fulu_fork_epoch=$(grep 'fulu_fork_epoch:' $config_file | awk '{print $2}')
slots_per_epoch=32
node_count=$(grep -w 'count:' $config_file | awk '{print $2}')

# make sure we have sudo permissions for tc
echo "Requesting sudo permissions to run tc on containers ... run at your own risk!"
sudo -v

# If exists, remove any existing enclave with the same name to ensure a clean start
if [ "$(kurtosis enclave ls | grep -w $enclave_name | wc -l)" -ne 0 ]; then
    kurtosis enclave rm -f $enclave_name
fi

# Start a new enclave with the specified configuration file
kurtosis run --enclave $enclave_name github.com/ethpandaops/ethereum-package --args-file $config_file

# start timing script in the background, get its pid so we can wait for it later
./$timing_script $config_file &
timing_pid=$!
echo "timing script started in the background with pid $timing_pid"

# get_node_progress() {
#     node=$1
#     block_number=$(docker exec $(docker ps --filter name=^/el-0*$node --quiet) \
#         geth attach --datadir='data/geth/execution-data' --exec 'eth.blockNumber')
#     echo -e "el-$node:\t$block_number"
# }

get_node_progress() {
    node=$1
    container_id=$(docker ps --filter name=^/el-0*$node --quiet)
    rpc_port=$(docker port $container_id 8545/tcp | cut -d: -f2)
    block_number=$(curl -s -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        http://localhost:$rpc_port | jq -r .result)
    txpool_status=$(curl -s -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"txpool_status","params":[],"id":1}' \
        http://localhost:$rpc_port | jq -r .result)
    txpool_pending=$(echo $txpool_status | jq -r .pending)
    txpool_queued=$(echo $txpool_status | jq -r .queued)
    echo -e "el-$node:\tBlock:$((16#${block_number:2})) | \
    PendingTXs:$((16#${txpool_pending:2})) | \
    Queued TXs: $((16#${txpool_queued:2}))"
}

get_progress() {
    local progress=""
    for node in $(seq 1 $node_count); do
        progress="$progress\nel-$node:\t$(get_node_progress $node)"
    done
    echo -e "$progress"
}

# show some progress indicator by getting selected metrics from el nodes
(
while true; do
    progress=$(get_progress)
    echo -e "Current block numbers on all nodes:$progress"
    sleep 1
    tput cuu $((node_count+1)) && tput ed
done
) &
progress_pid=$!

# wait for timing script to finish
wait $timing_pid
# kill the progress indicator
kill $progress_pid || true

# Generate merged EL logs from all nodes
for node in $(seq 1 $node_count); do
    docker logs $(docker ps --filter name=^/el-0*$node --quiet) 2>&1 | sed -e "s/^/el-$node /" -e "s/\[/ \[/";
done | sort -s -k3,3 > $logfile

echo -e "\nChecking for conversion logs"
grep -i "conver" $logfile || echo "No conversion logs found"

echo -e "\nChecking for errors"
grep -i "ERROR" $logfile || echo "No ERROR logs found"

# enclave is stopped by the trap, but we keep the data for further investigation if needed

#!/bin/bash
set -e
set -o pipefail

# This script is used to test the fusaka transition setup in a Kurtosis enclave.
# It runs the Ethereum package in a new enclave, waits for 2 minutes to allow logs
# to accumulate, and then collects and filters the logs from each node to display
# any ERROR or WARN messages.

config_file="test-fusaka-transition-01.yaml"
timing_file="timing-01.yaml"
enclave_name="test-fusaka-transition"
logfile="${config_file%.*}.log"

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

# Remove any existing enclave with the same name to ensure a clean start
kurtosis enclave rm -f $enclave_name || true

# Start a new enclave with the specified configuration file
kurtosis run --enclave $enclave_name github.com/ethpandaops/ethereum-package --args-file $config_file

# start timing script in the background, get it\s pid so we can wait for it later
./timing-01.sh $config_file &
timing_pid=$!
echo "timing script started in the background with pid $timing_pid"


# wait for timing script to finish
wait $timing_pid

# Generate merged EL logs from all nodes
for node in $(seq 1 $node_count); do
    docker logs $(docker ps --filter name=^/el-0*$node --quiet) 2>&1 | sed -e "s/^/el-$node /" -e "s/\[/ \[/";
done | sort -s -k3,3 > $logfile

echo -e "\nChecking for conversion logs"
grep -i "conver" $logfile || echo "No conversion logs found"

echo -e "\nChecking for errors"
grep -i "ERROR" $logfile || echo "No ERROR logs found"

# stop the enclave, but keep the data for further investigation if needed
kurtosis enclave stop $enclave_name